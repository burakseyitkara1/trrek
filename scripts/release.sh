#!/usr/bin/env bash
# Builds, signs (Developer ID + hardened runtime), notarizes and staples trrek, then tags the release and
# publishes it on GitHub with a DMG and a zip.
#
# Usage: scripts/release.sh --version X.Y.Z [--build N] [--profile NAME] [--identity NAME] [--no-publish]
#
# One-time setup on the release Mac:
#   xcrun notarytool store-credentials trrek --team-id <TEAM_ID>
# (asks for the Apple ID and an app-specific password; stored only in the login keychain).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=""
BUILD="$(git rev-list --count HEAD)"
PROFILE="trrek"
IDENTITY=""
PUBLISH=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build) BUILD="${2:?--build needs a value}"; shift 2 ;;
        --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --identity) IDENTITY="${2:?--identity needs a value}"; shift 2 ;;
        --no-publish) PUBLISH=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "release: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--version X.Y.Z is required"
TAG="v$VERSION"

SOURCE_VERSION="$(sed -nE 's/.*string = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' Sources/TrrekEngine/Version.swift)"
[[ "$SOURCE_VERSION" == "$VERSION" ]] || fail "Version.swift says $SOURCE_VERSION, not $VERSION"

if [[ $PUBLISH -eq 1 ]]; then
    [[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
    [[ "$(git branch --show-current)" == "main" ]] || fail "publish from main"
    git fetch -q origin
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not up to date with origin"
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists"
    gh auth status >/dev/null 2>&1 || fail "gh is not signed in"
fi

if [[ -z "$IDENTITY" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning || true)"
    IDENTITY="$(sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' <<<"$IDENTITIES" | head -n 1)"
fi
[[ -n "$IDENTITY" ]] || fail "no Developer ID Application identity found (pass --identity)"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "no notarization credentials in profile '$PROFILE' (run: xcrun notarytool store-credentials $PROFILE --team-id <TEAM_ID>)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="dist/trrek.app"
OUT="dist/release"
mkdir -p "$OUT"
ZIP="$OUT/trrek-$TAG.zip"
DMG="$OUT/trrek-$TAG.dmg"

notarize() {
    local file="$1" result status id
    echo "notarizing $(basename "$file") (this can take a few minutes)"
    result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json)"
    status="$(plutil -extract status raw - <<<"$result" 2>/dev/null || true)"
    id="$(plutil -extract id raw - <<<"$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        echo "$result" >&2
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        fail "notarization of $(basename "$file") ended with status '${status:-unknown}'"
    fi
}

TRREK_SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh --version "$VERSION" --build "$BUILD"

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname trrek -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "release artifacts: $ZIP $DMG"

if [[ $PUBLISH -eq 0 ]]; then
    echo "--no-publish: not tagging or publishing"
    exit 0
fi

git tag -a "$TAG" -m "trrek $VERSION"
git push origin "$TAG"
gh release create "$TAG" --verify-tag --title "trrek $VERSION" --generate-notes "$DMG" "$ZIP"
echo "published $TAG"
