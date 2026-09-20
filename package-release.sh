#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build-app.sh
release_arch="$(uname -m)"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
release_name="unnamedstudytool-${release_version}-macOS-${release_arch}.zip"
mkdir -p dist
codesign --verify --deep --strict unnamedstudytool.app
ditto -c -k --sequesterRsrc --keepParent unnamedstudytool.app "dist/$release_name"
(cd dist && shasum -a 256 "$release_name" > "$release_name.sha256")
echo "Packaged: dist/$release_name"
echo "This build is ad-hoc signed, not Apple-notarized."
