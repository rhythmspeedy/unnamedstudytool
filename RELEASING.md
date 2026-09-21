# Mac releases

Local builds are ad-hoc signed and are not Apple-notarized. The current task did not publish or upload a new release.

## Signed distribution

Apple requires a Developer ID Application signing identity and notarization credentials for the normal outside-App-Store distribution workflow. This Mac currently reports no valid signing identities. Do not put certificates, passwords, or API keys in this repository.

Once the owner has installed their Developer ID Application certificate and stored notarization credentials in a Keychain profile using Apple's tools, run:

```sh
STUDY_SIGN_IDENTITY="Developer ID Application: Your Organization (TEAMID)" \
STUDY_NOTARY_PROFILE="your-existing-keychain-profile" \
bash package-release.sh
```

The script builds, signs with hardened runtime and a secure timestamp, submits to Apple's notary service, staples and validates the ticket, checks Gatekeeper acceptance, and packages the stapled app with a checksum. It stops on failures. Without a notary profile it makes a non-notarized local package and labels it accordingly. This signing path has not been executed without the owner's certificate and credentials.

Apple references: [Developer ID](https://developer.apple.com/developer-id/) and [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Updates

Publish the architecture-specific ZIP and SHA-256 checksum to an explicitly approved GitHub release. Test the downloaded artifact on a clean Mac before publishing widely. Increment the version and build in Resources/Info.plist and update release notes before each release.

The app exposes the official release page in Settings and the app menu. Updates are user initiated: download, quit, replace the app bundle, reopen. Application Support data stays separate. No background installer, updater service, account, or network request is introduced at app startup.
