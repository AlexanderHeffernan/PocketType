#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"
swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
APP="$ROOT/build/PocketType.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PocketType" "$APP/Contents/MacOS/PocketType"
cp -R "$BIN/PocketType_Drift.bundle" "$APP/Contents/Resources/"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PocketType</string>
<key>CFBundleIdentifier</key><string>com.local.drift.typing</string>
<key>CFBundleName</key><string>PocketType</string>
<key>CFBundleDisplayName</key><string>PocketType</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>PocketType — independent Monkeytype companion, GPL-3.0-only</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Run: open \"$APP\""
