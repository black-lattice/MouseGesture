#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_DIR="$PWD/.build/sparkle-sdk"
bash scripts/prepare-sparkle.sh "$SPARKLE_DIR"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
APP_PATH="$PWD/dist/MouseGesture.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ARCHIVE_NAME="MouseGesture-$VERSION-universal"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/MouseGesture" "$APP_PATH/Contents/MacOS/MouseGesture"
mkdir -p "$APP_PATH/Contents/Frameworks"
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_DIR/Sparkle.framework" "$FRAMEWORK"
test -L "$FRAMEWORK/Versions/Current"
lipo "$FRAMEWORK/Sparkle" -verify_arch arm64 x86_64
otool -L "$APP_PATH/Contents/MacOS/MouseGesture" | grep -F '@rpath/Sparkle.framework/' >/dev/null
otool -l "$APP_PATH/Contents/MacOS/MouseGesture" | grep -F 'path @executable_path/../Frameworks ' >/dev/null
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_PATH/Contents/Info.plist")" = "AppIcon"
test -s "$APP_PATH/Contents/Resources/AppIcon.icns"

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    # Sign nested executables before their containing framework and app.
    helpers="$FRAMEWORK/Versions/Current"
    for component in "$helpers"/XPCServices/*.xpc "$helpers/Autoupdate" "$helpers/Updater.app" "$FRAMEWORK"; do
        codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$component"
    done
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --deep --strict --all-architectures "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/MouseGesture" -verify_arch arm64 x86_64
ditto -c -k --keepParent "$APP_PATH" "$PWD/dist/$ARCHIVE_NAME.zip"

python3 - "$APP_PATH" "$PWD/dist/$ARCHIVE_NAME.dmg" <<'PY'
import os
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="MouseGesture-dmg-") as stage:
    subprocess.run(["ditto", sys.argv[1], os.path.join(stage, "MouseGesture.app")], check=True)
    os.symlink("/Applications", os.path.join(stage, "Applications"))
    subprocess.run(["hdiutil", "create", "-volname", "MouseGesture", "-srcfolder", stage,
                    "-format", "UDZO", "-ov", sys.argv[2]], check=True)
PY
hdiutil verify "$PWD/dist/$ARCHIVE_NAME.dmg"
(
    cd dist
    shasum -a 256 "$ARCHIVE_NAME.zip" "$ARCHIVE_NAME.dmg" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
echo "已生成：$APP_PATH"
echo "已生成：$PWD/dist/$ARCHIVE_NAME.zip"
echo "已生成：$PWD/dist/$ARCHIVE_NAME.dmg"
