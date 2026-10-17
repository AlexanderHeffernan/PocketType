#!/bin/bash
# Install the latest public PocketType release. No sudo or quarantine stripping.
set -euo pipefail
INSTALL_DIR="$HOME/Applications"
DEST="$INSTALL_DIR/PocketType.app"
mkdir -p "$INSTALL_DIR"
STAGE="$(mktemp -d "$INSTALL_DIR/.pockettype-install.XXXXXX")"
cleanup() {
    if [ -d "$STAGE/previous.app" ] && [ ! -e "$DEST" ]; then
        mv "$STAGE/previous.app" "$DEST" || { echo "Previous app preserved at $STAGE/previous.app" >&2; return; }
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
# Resolve latest once so the checksum and archive always come from the same release.
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    https://api.github.com/repos/AlexanderHeffernan/PocketType/releases/latest -o "$STAGE/release.json"
TAG="$(plutil -extract tag_name raw -o - "$STAGE/release.json")"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
BASE="https://github.com/AlexanderHeffernan/PocketType/releases/download/$TAG"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/PocketType.zip" -o "$STAGE/PocketType.zip"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"
CHECKSUM="$(awk '$2 == "PocketType.zip" {print}' "$STAGE/SHA256SUMS")"
[[ "$CHECKSUM" =~ ^[[:xdigit:]]{64}[[:space:]]+PocketType.zip$ ]] || { echo 'Invalid release checksum' >&2; exit 1; }
printf '%s\n' "$CHECKSUM" > "$STAGE/archive.sha256"
(cd "$STAGE" && shasum -a 256 -c archive.sha256)
ditto -x -k "$STAGE/PocketType.zip" "$STAGE/unpacked"
APP="$STAGE/unpacked/PocketType.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" = com.local.drift.typing ] || exit 1
[ -x "$APP/Contents/MacOS/PocketType" ] || exit 1
codesign --verify --deep --strict "$APP"
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    [ ! -L "$DEST" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")" = com.local.drift.typing ] \
        || { echo "Refusing to replace an unrelated app or symlink at $DEST" >&2; exit 1; }
fi
if pgrep -x PocketType >/dev/null; then
    osascript -e 'tell application id "com.local.drift.typing" to quit'
    for ((i=0; i<40; i++)); do
        pgrep -x PocketType >/dev/null || break
        sleep 0.25
    done
    if pgrep -x PocketType >/dev/null; then
        echo 'PocketType is still closing. Quit it before running the installer again.' >&2
        exit 1
    fi
fi
if [ -e "$DEST" ]; then mv "$DEST" "$STAGE/previous.app"; fi
mv "$APP" "$DEST"
echo "Installed $DEST. Press Option–Space to practise. Future updates are in Settings → Updates."
open -n "$DEST"
