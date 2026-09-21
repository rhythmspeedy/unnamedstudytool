#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -n "${STUDY_NOTARY_PROFILE:-}" && -z "${STUDY_SIGN_IDENTITY:-}" ]]; then
  echo "Notarization requires STUDY_SIGN_IDENTITY (a Developer ID Application certificate)." >&2
  exit 1
fi
bash build-app.sh
release_arch="$(uname -m)"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
release_name="unnamedstudytool-${release_version}-macOS-${release_arch}.zip"
mkdir -p dist
codesign --verify --deep --strict unnamedstudytool.app
ditto -c -k --sequesterRsrc --keepParent unnamedstudytool.app "dist/$release_name"
if [[ -n "${STUDY_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "dist/$release_name" --keychain-profile "$STUDY_NOTARY_PROFILE" --wait
  xcrun stapler staple unnamedstudytool.app
  xcrun stapler validate unnamedstudytool.app
  spctl --assess --type execute --verbose unnamedstudytool.app
  ditto -c -k --sequesterRsrc --keepParent unnamedstudytool.app "dist/$release_name"
fi
(cd dist && shasum -a 256 "$release_name" > "$release_name.sha256")
echo "Packaged: dist/$release_name"
if [[ -n "${STUDY_NOTARY_PROFILE:-}" ]]; then
  echo "Developer ID signed and Apple-notarized."
else
  echo "This build is not Apple-notarized."
fi
