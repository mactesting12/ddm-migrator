#!/usr/bin/env bash
# Build "DDM Migrator.app" — a double-clickable, Dock-visible macOS app bundle
# from the SwiftPM release binary, with the generated app icon.
#
# Usage:  scripts/build-app.sh
# Output: build/DDM Migrator.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DDM Migrator.app"
ICONSET="build/AppIcon.iconset"

echo "▸ Building release binary…"
swift build -c release

echo "▸ Rendering app icon…"
swift scripts/make-icon.swift app-icon/icon-1024.png

echo "▸ Generating .iconset / .icns…"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz       app-icon/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png"      >/dev/null
  sips -z $((sz*2)) $((sz*2)) app-icon/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DDMMigratorApp "$APP/Contents/MacOS/DDMMigratorApp"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DDM Migrator</string>
  <key>CFBundleDisplayName</key><string>DDM Migrator</string>
  <key>CFBundleExecutable</key><string>DDMMigratorApp</string>
  <key>CFBundleIdentifier</key><string>com.machinerysoftware.ddm-migrator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Refresh icon cache so Finder/Dock pick up the new icon immediately.
touch "$APP"
echo "✓ Built: $APP"
