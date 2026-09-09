#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES_PATH="${1:?릴리즈 설명 파일을 지정해 주세요.}"
test -f "$NOTES_PATH"
if [ -n "$(git status --porcelain)" ]; then
    printf '소스 변경 사항을 먼저 커밋해 주세요.\n' >&2
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
TAG="v$VERSION"
PREVIOUS_TAG=$(git tag --list 'v[0-9]*' --sort=-version:refname | head -1)
python3 - "$PREVIOUS_TAG" "$VERSION" <<'PY'
import sys
import plistlib
import subprocess
previous, current = sys.argv[1:]
parts = [int(part) for part in previous.removeprefix("v").split(".")]
parts[2] += 1
expected = ".".join(map(str, parts))
if current != expected:
    raise SystemExit(f"다음 배포 버전은 {expected}이어야 합니다. 현재 값: {current}")
with open("Info.plist", "rb") as source:
    current_info = plistlib.load(source)
previous_info = plistlib.loads(subprocess.check_output(["git", "show", f"{previous}:Info.plist"]))
if int(current_info["CFBundleVersion"]) <= int(previous_info["CFBundleVersion"]):
    raise SystemExit("이전 릴리즈보다 빌드 번호를 올려 주세요.")
PY
if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    printf '이미 존재하는 버전입니다: %s\n' "$TAG" >&2
    exit 1
fi
swift test --arch arm64
bash scripts/prepare-update.sh "$NOTES_PATH"
git tag -a "$TAG" -m "Dalbear $TAG"
git push origin HEAD:main "$TAG"
# 파일 업로드가 모두 끝난 뒤에만 최신 릴리즈로 공개합니다.
gh release create "$TAG" "dist/updates/$TAG/"* --repo murse2000/Dalbear \
    --draft --verify-tag --title "Dalbear $TAG" --notes-file "$NOTES_PATH"
gh release edit "$TAG" --repo murse2000/Dalbear --draft=false --latest
