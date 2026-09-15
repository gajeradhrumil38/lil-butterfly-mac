#!/bin/bash
set -euo pipefail

REPOSITORY="gajeradhrumil38/lil-butterfly-mac"
RELEASE_API="https://api.github.com/repos/$REPOSITORY/releases/latest"
TEMP_DIR="$(mktemp -d -t butterfly-install)"
ARCHIVE_PATH="$TEMP_DIR/Butterfly.zip"
EXTRACT_DIR="$TEMP_DIR/extracted"
DESTINATION="/Applications/Butterfly.app"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Butterfly can only be installed on a Mac."
    exit 1
fi

echo "🦋 Finding the newest Butterfly…"
RELEASE_JSON="$(curl -fsSL "$RELEASE_API")" || {
    echo "Could not find Butterfly. Please check the internet connection and try again."
    exit 1
}

DOWNLOAD_URL="$(
    printf '%s\n' "$RELEASE_JSON" |
        awk -F '"' '/browser_download_url/ && /Butterfly-.*\.zip/ { print $4; exit }'
)"

case "$DOWNLOAD_URL" in
    https://github.com/gajeradhrumil38/lil-butterfly-mac/releases/download/*/Butterfly-*.zip) ;;
    *)
        echo "The newest Butterfly download is not ready yet."
        exit 1
        ;;
esac

echo "Downloading Butterfly…"
curl -fL --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"

SOURCE_APP="$(find "$EXTRACT_DIR" -maxdepth 2 -type d -name "Butterfly.app" -print -quit)"
if [[ -z "$SOURCE_APP" ]]; then
    echo "The download did not contain Butterfly.app."
    exit 1
fi

osascript -e 'tell application "Butterfly" to quit' >/dev/null 2>&1 || true

if [[ -w "/Applications" ]]; then
    ditto "$SOURCE_APP" "$DESTINATION"
    xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true
else
    echo "Your Mac may ask for its password to finish installing."
    sudo ditto "$SOURCE_APP" "$DESTINATION"
    sudo xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true
fi

open "$DESTINATION"
echo
echo "Butterfly is installed. Look for 🦋 at the top of the screen."
