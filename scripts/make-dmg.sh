#!/usr/bin/env bash
# Builds trrek's compressed, read-only disk image from an app bundle: the app, a shortcut to /Applications, the
# window background (Resources/dmg/background.tiff, in a hidden .background folder) and Finder's view settings
# (Resources/dmg/DS_Store, made by scripts/make-dmg-layout.sh), on a volume named "trrek" (the view settings find
# the background by that name). Signing and notarizing are up to the caller.
# Usage: scripts/make-dmg.sh <path/to/trrek.app> <out.dmg>
set -euo pipefail
cd "$(dirname "$0")/.."

[[ $# -eq 2 ]] || { echo "usage: $0 <path/to/trrek.app> <out.dmg>" >&2; exit 2; }
APP="$1"
DESTINATION="$2"
[[ -d "$APP" ]] || { echo "no app at $APP" >&2; exit 1; }
for file in Resources/dmg/background.tiff Resources/dmg/DS_Store; do
    [[ -f "$file" ]] || { echo "missing $file" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/trrek"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/trrek.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/dmg/background.tiff "$STAGE/.background/background.tiff"
cp Resources/dmg/DS_Store "$STAGE/.DS_Store"

# HFS+ like the volume the view settings were made on, so Finder resolves the background picture they point to.
rm -f "$DESTINATION"
hdiutil create -quiet -volname trrek -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DESTINATION"
echo "built $DESTINATION"
