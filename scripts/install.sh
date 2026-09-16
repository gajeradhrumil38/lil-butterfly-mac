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

# A little butterfly grows on screen, line by line, top to bottom, while the
# real download happens in the background — a small flourish rather than a
# bare progress bar. Paced deliberately slow (not tied to actual download
# speed, which is usually too fast to see) so it reads as an animation
# instead of a flicker; if the download finishes before the art does, it
# keeps drawing anyway, and if the download runs long, it flutters in place
# until done rather than just sitting on a finished picture.
draw_butterfly_download() {
    local url="$1" out="$2"
    local frame=(
        " _--_                                     _--_"
        "/#()# #\         0             0         /# #()#\\"
        "|()##  \#\_       \           /       _/#/  ##()|"
        "|#()##-=###\_      \         /      _/###=-##()#|"
        " \#()#-=##  #\_     \       /     _/#  ##=-#()#/"
        "  |#()#--==### \_    \     /    _/ ###==--#()#|"
        "  |#()##--=#    #\_   \!!!/   _/#    #=--##()#|"
        "   \#()##---===####\   O|O   /####===---##()#/"
        "    |#()#____==#####\ / Y \ /#####==____#()#|"
        "     \###______######|\/#\/|######______###/"
        "        ()#O#/      ##\_#_/##      \#O#()"
        "       ()#O#(__-===###/ _ \###===-__)#O#()"
        "      ()#O#(   #  ###_(_|_)_###  #   )#O#()"
        "      ()#O(---#__###/ (_|_) \###__#---)O#()"
        "      ()#O#( / / ##/  (_|_)  \## \ \ )#O#()"
        "      ()##O#\_/  #/   (_|_)   \#  \_/#O##()"
        "       \)##OO#\ -)    (_|_)    (- /#OO##(/"
        "        )//##OOO*|    / | \    |*OOO##\\("
        "        |/_####_/    ( /X\ )    \_####_\|"
        "       /X/ \__/       \___/       \__/ \X\\"
        "      (#/                               \#)"

    )

    curl -fL -s "$url" -o "$out" &
    local curl_pid=$!

    for line in "${frame[@]}"; do
        printf '  %s\n' "$line"
        sleep 0.1
    done

    local flutter=("  ~ fluttering closer ~" "  ~ almost here ~")
    local i=0
    while kill -0 "$curl_pid" 2>/dev/null; do
        printf '\r%s' "${flutter[$((i % ${#flutter[@]}))]}"
        i=$((i + 1))
        sleep 0.35
    done
    printf '\r%*s\r' "24" ""

    if ! wait "$curl_pid"; then
        echo "Could not download Butterfly. Please check the internet connection and try again."
        exit 1
    fi
}

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
draw_butterfly_download "$DOWNLOAD_URL" "$ARCHIVE_PATH"
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
