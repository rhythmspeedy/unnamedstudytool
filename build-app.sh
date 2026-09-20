#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$(pwd)/unnamedstudytool.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift Resources/MakeIcon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/unnamedstudytool "$APP/Contents/MacOS/unnamedstudytool"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $APP"
