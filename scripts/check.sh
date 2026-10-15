#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

# Execute only the pure recognition tests; do not build or launch the application.
cat Sources/GestureCore/GestureRecognizer.swift Tests/GestureCoreTests.swift > "$CHECK_DIR/main.swift"
xcrun swift "$CHECK_DIR/main.swift"

# Check binding persistence in an isolated preferences domain; never touch user settings.
cat Sources/GestureCore/GestureRecognizer.swift > "$CHECK_DIR/preferences.swift"
sed '/^import GestureCore$/d' Sources/MouseGesture/{GestureAction,CustomAction,MouseButtonBinding,Preferences}.swift >> "$CHECK_DIR/preferences.swift"
cat Tests/PreferencesTests.swift Tests/CustomActionsTests.swift Tests/PreferencesMigrationTests.swift Tests/MouseButtonPreferencesTests.swift >> "$CHECK_DIR/preferences.swift"
xcrun swift "$CHECK_DIR/preferences.swift"

# Validate disk persistence across process exits using release optimization.
cat Sources/GestureCore/GestureRecognizer.swift > "$CHECK_DIR/persistence.swift"
sed '/^import GestureCore$/d' Sources/MouseGesture/{GestureAction,CustomAction,MouseButtonBinding,Preferences}.swift >> "$CHECK_DIR/persistence.swift"
cat Tests/PersistenceProcessTests.swift >> "$CHECK_DIR/persistence.swift"
xcrun swiftc -O "$CHECK_DIR/persistence.swift" -o "$CHECK_DIR/persistence"
python3 - "$CHECK_DIR/persistence" <<'PY'
import subprocess
import sys
import uuid

suite = "MouseGesture.ProcessTests." + str(uuid.uuid4())
try:
    for mode in ["write", "migrate", "read", "edit", "readEdited", "delete", "readDeleted"]:
        subprocess.run([sys.argv[1], suite, mode], check=True)
    print("独立进程持久化测试通过：7 个阶段")
finally:
    subprocess.run([sys.argv[1], suite, "cleanup"], check=True)
PY

# A bare executable has no app bundle ID, so it cannot catch installed-app startup bugs.
# Compile the production convenience initializer and run it in a real .app as well.
cat Sources/GestureCore/GestureRecognizer.swift > "$CHECK_DIR/startup.swift"
sed '/^import GestureCore$/d' Sources/MouseGesture/{GestureAction,CustomAction,MouseButtonBinding,Preferences}.swift >> "$CHECK_DIR/startup.swift"
cat Tests/PreferencesStartupTests.swift >> "$CHECK_DIR/startup.swift"
xcrun swiftc -O "$CHECK_DIR/startup.swift" -o "$CHECK_DIR/startup"
python3 - "$CHECK_DIR/startup" "$CHECK_DIR" <<'PY'
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

domain = "MouseGesture.StartupTests." + str(uuid.uuid4())
app = os.path.join(sys.argv[2], "Startup.app", "Contents")
os.makedirs(os.path.join(app, "MacOS"))
installed = os.path.join(app, "MacOS", "Startup")
shutil.copy2(sys.argv[1], installed)
with open(os.path.join(app, "Info.plist"), "wb") as file:
    plistlib.dump({"CFBundleIdentifier": domain, "CFBundleExecutable": "Startup",
                  "CFBundlePackageType": "APPL"}, file)
try:
    for binary, mode in [(sys.argv[1], "write"), (installed, "installed"),
                         (sys.argv[1], "read"), (sys.argv[1], "cleanup"),
                         (installed, "fresh")]:
        subprocess.run([binary, domain, mode], check=True)
    print("安装版配置初始化与共享测试通过：5 个阶段")
finally:
    subprocess.run([sys.argv[1], domain, "cleanup"], check=True)
PY

# Exercise native recording events in a hidden test window, without posting system events.
cat Sources/GestureCore/GestureRecognizer.swift > "$CHECK_DIR/recording.swift"
sed '/^import GestureCore$/d' Sources/MouseGesture/{GestureAction,CustomAction,MouseButtonBinding,Preferences,ShortcutRecorder,AppState,AppState+MouseButtons,ActionExecutor,GestureTarget,GestureTargetRequest,MouseButtonMonitor,GestureMonitor,TrailOverlay,GestureRecordingView}.swift >> "$CHECK_DIR/recording.swift"
cat Tests/ShortcutCaptureTests.swift Tests/GestureRecordingTests.swift Tests/TrailLifecycleTests.swift Tests/TrailRenderingTests.swift Tests/PerformanceTests.swift Tests/MouseButtonTests.swift Tests/GestureTargetTests.swift Tests/GestureReliabilityTests.swift >> "$CHECK_DIR/recording.swift"
xcrun swift "$CHECK_DIR/recording.swift"

for ARCH in x86_64 arm64; do
    mkdir -p "$CHECK_DIR/$ARCH"
    xcrun swiftc -swift-version 5 -sdk "$SDK_PATH" -target "$ARCH-apple-macosx13.0" \
        -emit-module -module-name GestureCore Sources/GestureCore/*.swift \
        -emit-module-path "$CHECK_DIR/$ARCH/GestureCore.swiftmodule"
    xcrun swiftc -swift-version 5 -sdk "$SDK_PATH" -target "$ARCH-apple-macosx13.0" \
        -typecheck -I "$CHECK_DIR/$ARCH" Sources/MouseGesture/*.swift
    echo "类型检查通过：$ARCH"
done
plutil -lint Resources/Info.plist
iconutil -c iconset Resources/AppIcon.icns -o "$CHECK_DIR/AppIcon.iconset"
test -s "$CHECK_DIR/AppIcon.iconset/icon_512x512@2x.png"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' Resources/Info.plist)" = "AppIcon"
echo "应用图标资源检查通过"
git diff --check
