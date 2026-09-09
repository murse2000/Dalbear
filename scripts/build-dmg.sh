#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/MouseWheelFix.app/Contents/Info.plist)
DMG_PATH="$PWD/dist/Dalbear-${VERSION}-arm64.dmg"
if [ ! -x .build/dmg-tools/bin/dmgbuild ]; then
    python3 -m venv .build/dmg-tools
    .build/dmg-tools/bin/pip install 'dmgbuild==1.6.5'
fi
swift packaging/dmg-background.swift "$PWD/.build/dalbear-dmg-background.tiff"
swiftc packaging/dmg-bookmark.swift -o .build/dmg-bookmark
.build/dmg-tools/bin/python packaging/build-dmg.py "$DMG_PATH"
cp packaging/설치안내.txt dist/Dalbear-설치안내.txt
hdiutil verify "$DMG_PATH"
printf '설치 파일 생성 완료: %s\n' "$DMG_PATH"
