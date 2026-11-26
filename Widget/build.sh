#!/bin/bash
# Baut Token-Widget.app (Intel + Apple-Chip, ab macOS 13). Braucht die Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --show-sdk-path)
APP=Token-Widget.app/Contents
mkdir -p "$APP/MacOS"
swiftc -O -sdk "$SDK" -target arm64-apple-macos13 main.swift -o /tmp/tw_arm
swiftc -O -sdk "$SDK" -target x86_64-apple-macos13 main.swift -o /tmp/tw_x86
lipo -create /tmp/tw_arm /tmp/tw_x86 -output "$APP/MacOS/Token-Widget"
rm /tmp/tw_arm /tmp/tw_x86
cp Info.plist "$APP/Info.plist"
codesign --force -s - Token-Widget.app
echo "Fertig: $(pwd)/Token-Widget.app"
