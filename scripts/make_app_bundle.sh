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
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Butterfly "$APP/Contents/MacOS/Butterfly"
cp -R .build/release/Butterfly_Butterfly.bundle "$APP/Contents/Butterfly_Butterfly.bundle"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleDisplayName</key>
  <string>Butterfly</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSCalendarsUsageDescription</key>
  <string>Butterfly uses your calendar only when you enable meeting reminders.</string>
</dict>
</plist>
PLIST

echo "Built $APP — drag it into /Applications, or double-click to run it in place."
