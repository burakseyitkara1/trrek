#!/usr/bin/env bash
# Regenerates Resources/dmg/DS_Store: Finder's view settings for trrek's disk image window (icon view, no toolbar,
# 640x400, 128-point icons, the background picture, the app and the Applications shortcut in place). Run it by hand
# on a Mac after changing the window's layout or Resources/dmg/background.tiff; macOS asks once to let the terminal
# control Finder. Needs dist/trrek.app (`make app`).
# Usage: scripts/make-dmg-layout.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/trrek.app"
[[ -d "$APP" ]] || { echo "build the app first: make app" >&2; exit 1; }
VOLUME="trrek"
[[ ! -e "/Volumes/$VOLUME" ]] || { echo "/Volumes/$VOLUME is already mounted; eject it first" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "/Volumes/$VOLUME" 2>/dev/null || true; rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/dmg/background.tiff "$STAGE/.background/background.tiff"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/layout.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/layout.dmg"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "trrek.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 1
cp "/Volumes/$VOLUME/.DS_Store" Resources/dmg/DS_Store
echo "wrote Resources/dmg/DS_Store"
