#!/bin/sh
# Build a zip to hand to someone else: the app plus its installer.
set -e
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
          build/Pet.app/Contents/Info.plist 2>/dev/null || echo 1.0)
STAGE="build/dist/DesktopPet"
ZIP="build/DesktopPet-$VERSION.zip"

./build.sh --no-install >/dev/null

rm -rf "build/dist" "$ZIP"
mkdir -p "$STAGE"
cp -R build/Pet.app "$STAGE/Pet.app"
cp install.sh "$STAGE/install.sh"


cat > "$STAGE/README.txt" <<'TXT'
Desktop Pet
===========

A little animated pet that lives on your screen. It wanders, grooms itself
and falls asleep — and, with one extra command, reacts to what Claude Code is
doing: typing at a tiny laptop while a tool runs, thinking between steps,
raising a "!" when Claude needs you, celebrating when a turn finishes.

INSTALL
-------
Open Terminal, cd into this folder, and run:

    sh install.sh

That installs the app to ~/Applications, adds a `pet` command, and starts it.
Nothing else on your system is touched. No Homebrew, no Python.

MAKE IT REACT TO YOUR CODING AGENT  (optional)
----------------------------------------------
    pet plugin install

Registers hooks so your coding agent can tell the pet what it is doing —
Claude Code, Codex, Gemini CLI and opencode are supported, and whichever of
them you have installed is set up. It backs up each config file first and
leaves your other hooks alone. Start a new session afterwards.

    pet plugin install codex    just one of them
    pet plugin status           see what is registered
    pet plugin uninstall        remove it again

THE PET COMMAND
---------------
    pet status              what the pet is doing right now
    pet skins               list skins
    pet skin dog            switch skin
    pet show | hide         hide the pet itself
    pet tray hide           hide the menu bar icon (pet tray show brings it back)
    pet config              where skins and settings live
    pet config set <path>   move that folder
    pet uninstall           remove the app, the command and the plugin
    pet help                everything else

USING THE PET
-------------
  • Drag it to move it; it stays where you drop it.
  • Double-click it to toggle "chase the cursor".
  • Menu bar 🐈 : show/hide, pick a skin, import/export skins, quit.

Skins are plain JSON files in ~/.config/pet/skins — copy one and edit the
colours to make your own, or use `pet skins dir` to find them.

You can also use spritesheet characters from https://codex-pets.net :

    pet pets install <id>       download and install one
    pet skin <id>               switch to it

NOTE ON THE FIRST LAUNCH
------------------------
This app is not signed with an Apple Developer ID, so macOS would normally
warn that it is from an unidentified developer. Running install.sh clears
that for you. If you drag Pet.app out manually instead and macOS blocks it,
right-click the app and choose Open, or run:

    xattr -dr com.apple.quarantine /path/to/Pet.app

REQUIREMENTS
------------
macOS 12 or later, Intel or Apple Silicon.
TXT

ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"
rm -rf build/dist

echo "package: $(pwd)/$ZIP"
echo "size:    $(du -h "$ZIP" | cut -f1)"
