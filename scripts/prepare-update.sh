#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES_PATH="${1:?릴리즈 설명 파일을 지정해 주세요.}"
test -f "$NOTES_PATH"
bash scripts/build-dmg.sh
SPARKLE_BIN="$PWD/.build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Info.plist)
if [ "$("$SPARKLE_BIN/generate_keys" --account com.dalbear.updates -p)" != "$PUBLIC_KEY" ]; then
    printf '현재 앱의 공개 키와 키체인의 업데이트 서명 키가 일치하지 않습니다.\n' >&2
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
UPDATE_PATH="$PWD/dist/updates/v$VERSION"
if [ -e "$UPDATE_PATH" ]; then
    printf '이미 준비된 업데이트가 있습니다: %s\n' "$UPDATE_PATH" >&2
    exit 1
fi
STAGING_PATH=$(mktemp -d "$PWD/.build/dalbear-update.XXXXXX")
trap 'rm -rf "$STAGING_PATH"' EXIT
cp "dist/Dalbear-$VERSION-arm64.dmg" "$STAGING_PATH/"
cp "$NOTES_PATH" "$STAGING_PATH/Dalbear-$VERSION-arm64.md"
"$SPARKLE_BIN/generate_appcast" --account com.dalbear.updates \
    --download-url-prefix "https://github.com/murse2000/Dalbear/releases/download/v$VERSION/" \
    --link "https://github.com/murse2000/Dalbear/releases/tag/v$VERSION" \
    --embed-release-notes --maximum-deltas 0 "$STAGING_PATH"
"$SPARKLE_BIN/sign_update" --account com.dalbear.updates --verify "$STAGING_PATH/appcast.xml"
cp packaging/설치안내.txt "$STAGING_PATH/Dalbear-Install-ko.txt"
python3 - "$STAGING_PATH" <<'PY'
import hashlib
import sys
from pathlib import Path
root = Path(sys.argv[1])
files = sorted(p for p in root.iterdir() if p.is_file())
(root / "SHA256SUMS.txt").write_text("".join(
    hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n" for p in files
))
PY
mkdir -p "$(dirname "$UPDATE_PATH")"
mv "$STAGING_PATH" "$UPDATE_PATH"
printf '서명된 업데이트 준비 완료: %s\n' "$UPDATE_PATH"
