#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP_PATH="$PWD/dist/MouseWheelFix.app"
mkdir -p "$APP_PATH/Contents/MacOS"
FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP_PATH/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$FRAMEWORK_PATH"
ICONSET_PATH="$PWD/.build/Dalbear.iconset"
mkdir -p "$ICONSET_PATH" "$APP_PATH/Contents/Resources"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Dalbear/Dalbear.png --out "$ICONSET_PATH/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Assets/Dalbear/Dalbear.png --out "$ICONSET_PATH/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/Dalbear.icns"
cp "$BIN_DIR/MouseWheelFix" "$APP_PATH/Contents/MacOS/MouseWheelFix"
cp Info.plist "$APP_PATH/Contents/Info.plist"
ditto "$BIN_DIR/MouseWheelFix_AppLocalization.bundle" "$APP_PATH/Contents/Resources/MouseWheelFix_AppLocalization.bundle"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP_PATH/Contents/Resources/Sparkle-LICENSE.txt"
codesign --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
lipo -archs "$APP_PATH/Contents/MacOS/MouseWheelFix"
printf '앱 생성 완료: %s\n' "$APP_PATH"
