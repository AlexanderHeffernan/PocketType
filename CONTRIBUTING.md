# Contributing to PocketType

Please keep changes focused on the native companion. Monkeytype owns the typing engine, account system, and scoring; don't bypass its authentication or submit results through unsupported APIs.

## Before sending a pull request

1. Build on macOS 14+ with Swift 6 and the Xcode command-line tools.
2. Run `swift test` and `./build.sh`.
3. Launch `build/PocketType.app` and exercise the affected behaviour. For appearance changes, check the actual rendered app, not just the code.
4. Describe the change, verification, and any limitations. Do not include credentials, website storage, private desktop screenshots, or generated `.build`/`build` output.

For a bug report, include your macOS version, whether experimental glass is enabled, how to reproduce it, and whether it also occurs on the full Monkeytype website. Crop or redact screenshots before sharing.

By contributing, you agree that your contribution is licensed under this project's GPL-3.0-only licence.
