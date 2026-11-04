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

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid --version '$VERSION' (expected X.Y.Z)" >&2; exit 2; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "invalid --build '$BUILD' (expected digits)" >&2; exit 2; }

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

# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc signing changes the
# code hash on every build. Order: $TRREK_SIGN_IDENTITY, a Developer ID Application identity (the
# same one releases use, so local builds and released builds share one Accessibility grant), the
# self-signed "trrek Local Signing" identity (scripts/make-signing-identity.sh), then ad-hoc. When
# signing with an identity fails (for example a keychain prompt was denied), the build falls back
# to ad-hoc. Releases re-sign with the hardened runtime and notarize (scripts/release.sh).
IDENTITIES="$(security find-identity -v -p codesigning || true)"
IDENTITY=""
DEVELOPER_ID="$(sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' <<<"$IDENTITIES" | head -n 1)"
if [[ -n "${TRREK_SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$TRREK_SIGN_IDENTITY"
elif [[ -n "$DEVELOPER_ID" ]]; then
    IDENTITY="$DEVELOPER_ID"
elif grep -q "trrek Local Signing" <<<"$IDENTITIES"; then
    IDENTITY="trrek Local Signing"
fi
if [[ -n "$IDENTITY" ]] && ! codesign --force --deep --sign "$IDENTITY" "$APP"; then
    echo "warning: signing with '$IDENTITY' failed; signing ad-hoc instead (Accessibility must be granted again)" >&2
    IDENTITY=""
fi
if [[ -z "$IDENTITY" ]]; then
    codesign --force --sign - --deep "$APP"
fi
codesign -dv "$APP"
echo "built $APP ($VERSION, build $BUILD)"
