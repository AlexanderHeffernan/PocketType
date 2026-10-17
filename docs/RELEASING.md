# Releases and updates

Every push to `main` runs debug/release tests and packaged-app smoke checks on Apple Silicon and Intel. Only successful checks publish a universal release for that exact commit. Pull requests never publish. Releases are serialised; publishing uploads all assets to a draft before making it latest.

The first version is `1.0.0`. Subsequent pushes increment the patch version from reachable stable tags. Raise `CFBundleShortVersionString` in `Info.plist` for a minor/major release. Rerunning a released commit reuses its immutable version without replacing public assets.

## Signing

`SPARKLE_PRIVATE_KEY` must be configured as a repository Actions secret. Its public key is in `Info.plist`. CI signs both the appcast and archive with Sparkle and independently verifies them against that public key before publishing. Never commit/export the private key into the repository or logs. Local packaging uses the dedicated `PocketType` signing key in the login Keychain:

```sh
swift test
python3 -m unittest discover -s scripts -p 'test_*.py'
./scripts/package-release.sh 1.0.0
```

This creates local assets only; it does not publish. Keep the signing key backed up securely: existing apps cannot trust releases signed by a replacement key without a planned key migration.

## User experience

Settings → Updates provides a manual check and an automatic-checks switch. Automatic checks run approximately every six hours while the app is running. Users choose when to install and restart; background installation is disabled. Sparkle preserves the bundle identifier, preferences and persistent WebKit website data.

The feed is `https://github.com/AlexanderHeffernan/PocketType/releases/latest/download/appcast.xml`; archive URLs pin individual versions. Required signed feeds and verify-before-extraction reject unsigned/tampered updates.

## Gatekeeper limitation

Current releases are ad-hoc signed, **not Apple Developer ID signed or notarised**. Sparkle update signatures authenticate updates but do not remove first-install Gatekeeper warnings. `build.sh` supports a local `CODESIGN_IDENTITY`; adding notarisation and Apple credentials to CI is separate work. Do not describe these releases as notarised.

After changing release machinery, inspect the actual GitHub workflow and downloaded assets, verify signatures/checksums and launch, then exercise an installed older app through download, installation and relaunch. A green build alone is not an updater end-to-end test.
