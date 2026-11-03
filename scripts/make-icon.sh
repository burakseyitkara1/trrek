#!/usr/bin/env bash
# Builds an .icns app icon. Usage: scripts/make-icon.sh <out.icns>
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <out.icns>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$1"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/icon-1024.png"
ICONSET="$WORK/trrek.iconset"
mkdir -p "$ICONSET"

swift "$SCRIPT_DIR/render-icon.swift" "$MASTER"

# name:pixels pairs following Apple's iconset naming.
for entry in \
    icon_16x16:16 icon_16x16@2x:32 \
    icon_32x32:32 icon_32x32@2x:64 \
    icon_128x128:128 icon_128x128@2x:256 \
    icon_256x256:256 icon_256x256@2x:512 \
    icon_512x512:512 icon_512x512@2x:1024; do
    name="${entry%%:*}"
    px="${entry##*:}"
    sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
