#!/bin/bash
# Builds a release binary and wraps it into a minimal, double-clickable
# LilButterfly.app you can drag into /Applications. Not required for
# day-to-day development — `swift run` (or Run in Xcode) is enough for that.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="LilButterfly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LilButterfly "$APP/Contents/MacOS/LilButterfly"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Lil Butterfly</string>
  <key>CFBundleIdentifier</key>
  <string>com.you.lilbutterfly</string>
  <key>CFBundleExecutable</key>
  <string>LilButterfly</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP — drag it into /Applications, or double-click to run it in place."
