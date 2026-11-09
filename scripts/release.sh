#!/usr/bin/env bash
# Builds, signs (Developer ID + hardened runtime), notarizes and staples trrek, then tags the release and
# publishes it on GitHub with a DMG and a zip and the version's CHANGELOG.md section as its notes: in this
# repository, whose releases the app's update check reads. MIRROR_REPO, when set, also receives the release (it was
# burakseyitkara1/trrek-releases, which 0.4.0 and 0.4.1 read, until 0.4.2). --no-publish publishes nowhere.
#
# Publishing needs a successful run of the ci workflow for the exact commit being released. Pull request runs test a
# merge of the branch, not the squashed commit on main, so start one on main first and wait for it to pass:
#   gh workflow run ci --ref main && sleep 10 && gh run watch "$(gh run list --workflow ci --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')"
# --allow-missing-ci publishes without one (with a warning), for when GitHub Actions cannot run at all.
#
# Usage: scripts/release.sh --version X.Y.Z [--build N] [--profile NAME] [--identity NAME] [--no-publish]
#                           [--allow-missing-ci]
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
ALLOW_MISSING_CI=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build) BUILD="${2:?--build needs a value}"; shift 2 ;;
        --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --identity) IDENTITY="${2:?--identity needs a value}"; shift 2 ;;
        --no-publish) PUBLISH=0; shift ;;
        --allow-missing-ci) ALLOW_MISSING_CI=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "release: $*" >&2; exit 1; }

# A second repository that receives every release; "" (the default) publishes only here.
MIRROR_REPO=""
NOTES=""

# Prints the CHANGELOG section of version $1 (file $2, CHANGELOG.md by default): the lines under its
# "## [X.Y.Z]" heading up to the next "## [" heading, without link reference definitions ("[X.Y.Z]: https://…")
# and without leading and trailing blank lines. Prints nothing when the section is missing or empty.
changelog_section() {
    local version="$1" file="${2:-CHANGELOG.md}"
    awk -v heading="## [$version]" '
        index($0, "## [") == 1 {
            if (found) exit
            if (index($0, heading) == 1) { found = 1; next }
        }
        found && !/^\[[^]]+\]: / { lines[++n] = $0 }
        END {
            first = 1
            while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
            last = n
            while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
            for (i = first; i <= last; i++) print lines[i]
        }' "$file"
}

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
    COMMIT="$(git rev-parse HEAD)"
    if [[ $ALLOW_MISSING_CI -eq 1 ]]; then
        {
            echo "################################################################################"
            echo "WARNING: --allow-missing-ci: publishing $COMMIT without checking for a"
            echo "successful ci run. This release is built, tested and signed on this Mac only."
            echo "Run the ci workflow for $COMMIT as soon as GitHub Actions works again."
            echo "################################################################################"
        } >&2
    else
        CI_RUN="$(gh run list --commit "$COMMIT" --workflow ci --status success --limit 1 \
            --json databaseId --jq '.[0].databaseId // empty')" || fail "could not list the ci runs of $COMMIT"
        [[ -n "$CI_RUN" ]] || fail "no successful ci run for $COMMIT; run it with 'gh workflow run ci --ref main' and wait for it to pass (or pass --allow-missing-ci)"
        echo "ci run $CI_RUN passed for $COMMIT"
    fi
    if [[ -n "$MIRROR_REPO" ]]; then
        gh repo view "$MIRROR_REPO" >/dev/null 2>&1 || fail "the mirror repository $MIRROR_REPO is not reachable"
        ! gh release view "$TAG" --repo "$MIRROR_REPO" >/dev/null 2>&1 || fail "$MIRROR_REPO already has a release $TAG"
    fi
    NOTES="$(changelog_section "$VERSION")"
    [[ -n "$NOTES" ]] || fail "CHANGELOG.md has no section for $VERSION (a '## [$VERSION] - YYYY-MM-DD' heading with lines under it)"
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
NOTES_FILE="$OUT/trrek-$TAG-notes.md"

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
# The stripped executable's symbols, for crash reports of this release; kept on this Mac, never published.
rm -rf "$OUT/trrek-$TAG.dSYM"
cp -R dist/trrek.app.dSYM "$OUT/trrek-$TAG.dSYM"

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# The disk image: the app, the Applications shortcut, the window background and Finder's view settings.
scripts/make-dmg.sh "$APP" "$DMG"
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
# The notes are kept beside the artifacts (not in $WORK, which is removed on exit) so a failed upload can be redone.
printf '%s\n' "$NOTES" > "$NOTES_FILE"
gh release create "$TAG" --verify-tag --title "trrek $VERSION" --notes-file "$NOTES_FILE" --latest "$DMG" "$ZIP"
echo "published $TAG"

# The copy that 0.4.0 and 0.4.1 read for updates: the same files and notes.
if [[ -n "$MIRROR_REPO" ]]; then
    gh release create "$TAG" --repo "$MIRROR_REPO" --title "trrek $VERSION" --notes-file "$NOTES_FILE" "$DMG" "$ZIP" \
        || fail "$TAG is published here but not in $MIRROR_REPO; rerun: gh release create $TAG --repo $MIRROR_REPO --title \"trrek $VERSION\" --notes-file $NOTES_FILE $DMG $ZIP"
    echo "published $TAG in $MIRROR_REPO"
fi
