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
if [[ -n "${STUDY_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$STUDY_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built: $APP"
