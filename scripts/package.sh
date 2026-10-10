#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
APP_PATH="$PWD/dist/MouseGesture.app"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BIN_DIR/MouseGesture" "$APP_PATH/Contents/MacOS/MouseGesture"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --strict "$APP_PATH"
lipo -verify_arch arm64 x86_64 "$APP_PATH/Contents/MacOS/MouseGesture"
ditto -c -k --keepParent "$APP_PATH" "$PWD/dist/MouseGesture-universal.zip"
echo "已生成：$APP_PATH"
echo "已生成：$PWD/dist/MouseGesture-universal.zip"
