#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"
BUILD=(--package-path "$ROOT" -c "${CONFIGURATION:-release}")
for arg in "$@"; do
    case "$arg" in
        --universal) BUILD+=(--arch arm64 --arch x86_64) ;;
        *) echo "Usage: $0 [--universal]" >&2; exit 2 ;;
    esac
done
swift build "${BUILD[@]}"
BIN="$(swift build "${BUILD[@]}" --show-bin-path)"
APP="$ROOT/build/PocketType.app"
# Only generated output is replaced; never preserve stale signed resources.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/PocketType" "$APP/Contents/MacOS/PocketType"
ditto "$BIN/PocketType_Drift.bundle" "$APP/Contents/Resources/PocketType_Drift.bundle"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
if [ -n "${RELEASE_VERSION:-}" ]; then
    [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_VERSION" "$APP/Contents/Info.plist"
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE"
SIGN=(--force --sign "${CODESIGN_IDENTITY:--}")
if [ "${CODESIGN_IDENTITY:--}" != '-' ]; then
    SIGN+=(--options runtime --timestamp)
    for component in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
        codesign "${SIGN[@]}" "$FRAMEWORK/Versions/B/$component"
    done
    codesign "${SIGN[@]}" "$FRAMEWORK"
fi
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
echo "Run: open \"$APP\""
