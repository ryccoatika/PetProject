#!/bin/sh
# Build a drag-and-drop disk image: Pet.app beside an Applications shortcut.
set -e
cd "$(dirname "$0")"

VOLNAME="Desktop Pet"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
          build/Pet.app/Contents/Info.plist 2>/dev/null || echo 1.0)
DMG="build/DesktopPet-$VERSION.dmg"
STAGE="build/dmg"
RW="build/rw.dmg"

./build.sh --no-install >/dev/null

rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE/.background"
cp -R build/Pet.app "$STAGE/Pet.app"
ln -s /Applications "$STAGE/Applications"
build/pet dmgbg "$STAGE/.background/background.png"
cp build/Pet.app/Contents/Resources/Pet.icns "$STAGE/.VolumeIcon.icns"

# HFS+ so Finder can keep icon positions and the background in .DS_Store
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
               -format UDRW -ov "$RW"

MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | \
        sed -n 's|.*\(/Volumes/.*\)|\1|p' | head -1)
[ -n "$MOUNT" ] || { echo "could not mount the image"; exit 1; }

# Lay the window out. Needs permission to control Finder, which a terminal is
# not always granted, so the image is still valid if this part is refused.
#
# Skipped on a build machine: there is no one to look at the window, and a
# headless Finder tends to keep the volume open afterwards, which then makes
# the detach below fail. Set PET_DMG_LAYOUT=1 to force it on anyway.
if [ "${PET_DMG_LAYOUT:-auto}" = "0" ] || \
   { [ "${PET_DMG_LAYOUT:-auto}" = "auto" ] && [ -n "${CI:-}" ]; }; then
    echo "note: skipping the Finder layout on a build machine"
elif osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set background picture of opts to file ".background:background.png"
        set position of item "Pet.app" of container window to {170, 205}
        set position of item "Applications" of container window to {430, 205}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
then
    echo "window layout applied"
else
    echo "note: could not script Finder (permission) — image built without a custom layout"
fi

# a custom volume icon needs the folder's custom-icon bit
SetFile -a C "$MOUNT" 2>/dev/null || true
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

# Whoever just looked inside the volume (Finder, Spotlight) may still hold it
# open for a moment, so give the detach a few tries before forcing it. Errors
# stay on stderr here: a silent failure at this point is very hard to diagnose.
detached=0
for attempt in 1 2 3 4 5; do
    if hdiutil detach "$MOUNT" -quiet; then
        detached=1
        break
    fi
    echo "note: the volume is still busy, retrying the eject ($attempt)"
    sleep 2
done
if [ "$detached" -eq 0 ]; then
    hdiutil detach "$MOUNT" -force
fi

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

echo "disk image: $(pwd)/$DMG"
echo "size:       $(du -h "$DMG" | cut -f1)"
