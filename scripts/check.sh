#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

# Execute only the pure recognition tests; do not build or launch the application.
cat Sources/GestureCore/GestureRecognizer.swift Tests/GestureCoreTests.swift > "$CHECK_DIR/main.swift"
xcrun swift "$CHECK_DIR/main.swift"

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
git diff --check
