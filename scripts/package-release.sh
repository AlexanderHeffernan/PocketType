#!/bin/bash
# Creates local release assets only. Never uploads or publishes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: package-release.sh VERSION}"
OUT="$ROOT/build/distribution"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
RELEASE_VERSION="$VERSION" "$ROOT/build.sh" --universal
"$ROOT/build/PocketType.app/Contents/MacOS/PocketType" --smoke-test
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/PocketType.app" "$OUT/PocketType.zip"
SIGNING=(--account PocketType)
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then SIGNING=(--ed-key-file -); fi
if [ -n "${RELEASE_NOTES_FILE:-}" ]; then cp "$RELEASE_NOTES_FILE" "$OUT/PocketType.md"; fi
printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$TOOLS/generate_appcast" "${SIGNING[@]}" \
    --embed-release-notes --maximum-deltas 0 --download-url-prefix "https://github.com/AlexanderHeffernan/PocketType/releases/download/v$VERSION/" \
    --link "https://github.com/AlexanderHeffernan/PocketType" "$OUT"
python3 "$ROOT/scripts/release.py" verify "$OUT" "$VERSION"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$ROOT/build/PocketType.app/Contents/Info.plist")"
swift "$ROOT/scripts/verify-update.swift" "$OUT" "$PUBLIC_KEY"
(cd "$OUT" && shasum -a 256 PocketType.zip appcast.xml > SHA256SUMS)
echo "Release assets ready in $OUT (not published)"
