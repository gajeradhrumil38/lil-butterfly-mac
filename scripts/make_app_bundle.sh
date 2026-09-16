#!/bin/bash
# Builds a release binary and wraps it into a minimal, double-clickable
# Butterfly.app you can drag into /Applications. Not required for
# day-to-day development — `swift run` (or Run in Xcode) is enough for that.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_VERSION="${APP_VERSION:-1.0.0}"

swift build -c release

APP="Butterfly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Butterfly "$APP/Contents/MacOS/Butterfly"
# SwiftPM's generated Bundle.module accessor has shipped more than one
# implementation across toolchain versions: newer ones check
# Bundle.main.resourceURL (Contents/Resources) with a fallback chain, but the
# simpler variant (confirmed via a real crash log from a CI-built release)
# only checks Bundle.main.bundleURL — the .app's own top level, alongside
# Contents/. Since which one gets generated depends on the compiling
# toolchain, not our code, copy the bundle to every location either variant
# might look — it's a few small SVGs, duplicating it is cheap and this is the
# actual cause of "could not load resource bundle" crashing every release
# build on first launch (never caught by `swift run`, which doesn't use this
# script or a real .app bundle at all).
cp -R .build/release/Butterfly_Butterfly.bundle "$APP/Contents/Resources/Butterfly_Butterfly.bundle"
cp -R .build/release/Butterfly_Butterfly.bundle "$APP/Butterfly_Butterfly.bundle"
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Butterfly</string>
  <key>CFBundleIdentifier</key>
  <string>com.kavii.butterfly</string>
  <key>CFBundleExecutable</key>
  <string>Butterfly</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleDisplayName</key>
  <string>Butterfly</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSCalendarsUsageDescription</key>
  <string>Butterfly uses your calendar only when you enable meeting reminders.</string>
</dict>
</plist>
PLIST

echo "Built $APP — drag it into /Applications, or double-click to run it in place."
