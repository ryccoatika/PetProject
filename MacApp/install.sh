#!/bin/sh
# Desktop Pet installer.
#
#   sh install.sh              install (or update) the app and the `pet` command
#   sh install.sh --uninstall  remove them  (same as: pet uninstall)
#
# Installs only the pet. To make it react to Claude Code, afterwards run:
#   pet plugin install
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
APP_SRC="$DIR/Pet.app"
APP_DST="$HOME/Applications/Pet.app"
CLI_TARGET="$APP_DST/Contents/MacOS/Pet"

pick_bin_dir() {
    if [ -w /usr/local/bin ] 2>/dev/null; then echo /usr/local/bin
    else echo "$HOME/.local/bin"; fi
}

if [ "$1" = "--uninstall" ]; then
    if [ -x "$CLI_TARGET" ]; then exec "$CLI_TARGET" uninstall; fi
    pkill -f "Pet.app/Contents/MacOS/Pet" 2>/dev/null || true
    rm -rf "$APP_DST"
    rm -f /usr/local/bin/pet "$HOME/.local/bin/pet"
    echo "  ✓  removed the app and the pet command"
    exit 0
fi

[ -d "$APP_SRC" ] || { echo "Pet.app not found next to this script."; exit 1; }

echo "Installing Desktop Pet…"

# Downloaded files are quarantined; clear it so the app opens without the
# "unidentified developer" prompt.
xattr -dr com.apple.quarantine "$APP_SRC" 2>/dev/null || true

pkill -f "Pet.app/Contents/MacOS/Pet" 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
echo "  ✓  installed $APP_DST"

# The `pet` command is the same binary, symlinked so it tracks app updates.
BIN=$(pick_bin_dir)
mkdir -p "$BIN"
ln -sf "$CLI_TARGET" "$BIN/pet"
echo "  ✓  installed $BIN/pet"

open "$APP_DST"
echo
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) echo "  !  $BIN is not in your PATH. Add this to your shell profile:"
       echo "         export PATH=\"$BIN:\$PATH\""
       echo "" ;;
esac
echo "Done — the pet is on screen and the menu bar has a 🐈 icon."
echo
echo "  pet help              what the command can do"
echo "  pet plugin install    optional: make it react to Claude Code"
echo "  pet uninstall         remove everything"
