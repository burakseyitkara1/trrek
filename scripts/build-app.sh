#!/usr/bin/env bash
# Packages trrek as dist/trrek.app. Usage: scripts/build-app.sh [--version X.Y.Z] [--build N]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.0.0"
BUILD="1"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build) BUILD="${2:?--build needs a value}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

APP="dist/trrek.app"

swift build -c release --arch arm64 --product Trrek
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Trrek" "$APP/Contents/MacOS/trrek"

sed -e "s/\${VERSION}/$VERSION/g" -e "s/\${BUILD}/$BUILD/g" \
    Resources/Info.plist.in > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

scripts/make-icon.sh "$APP/Contents/Resources/AppIcon.icns"

if [[ -d Sources/Trrek/Resources ]]; then
    cp -R Sources/Trrek/Resources/. "$APP/Contents/Resources/"
fi

codesign --force --sign - --deep "$APP"
codesign -dv "$APP"
echo "built $APP ($VERSION, build $BUILD)"
