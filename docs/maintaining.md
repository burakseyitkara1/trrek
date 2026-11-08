# Maintaining trrek

Notes for the maintainer and contributors: signing, releasing, make targets and how the engine is put together. For using trrek, see the [README](../README.md); for contributing, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Keeping Accessibility permission across rebuilds

macOS ties the Accessibility grant to the app's code signature. `scripts/build-app.sh` signs with the first identity it finds: `$TRREK_SIGN_IDENTITY`, a "Developer ID Application" identity, the self-signed "trrek Local Signing" identity created by `scripts/make-signing-identity.sh`, and only then ad-hoc. With a Developer ID identity, local builds and released builds share one grant, which survives every update. Ad-hoc builds change their code hash on every build, so the grant is lost after each reinstall. The first build signed with an identity shows a one-time keychain prompt asking to let `codesign` use the key: choose Always Allow. When you switch identities (for example from ad-hoc or the local identity to Developer ID), macOS keeps the old grant tied to the old signature: quit trrek, run `tccutil reset Accessibility com.burakseyitkara.trrek`, reopen it and grant access once more.

## Publishing a release

Releases are built, signed with Developer ID and the hardened runtime, notarized, stapled and published from the release Mac with `make release VERSION=X.Y.Z` (`scripts/release.sh`; update `Sources/TrrekEngine/Version.swift` and the changelog first, from an up-to-date `main`). One-time setup: create an app-specific password for your Apple ID and store the notarization credentials in the login keychain with `xcrun notarytool store-credentials trrek --team-id <TEAM_ID>`. The release notes are the version's `CHANGELOG.md` section; the script stops before building when that section is missing. `scripts/release.sh --version X.Y.Z --no-publish` produces the notarized DMG and zip in `dist/release` without tagging or publishing anywhere. The tag-triggered workflow only checks that the tagged commit builds and passes the tests.

Publishing requires a successful run of the `ci` workflow for the exact commit being released. Pull request runs test a merge of the branch, not the squashed commit on `main`, so start one on `main` and wait for it to pass before releasing: `gh workflow run ci --ref main`. When GitHub Actions cannot run at all, `scripts/release.sh --version X.Y.Z --allow-missing-ci` publishes without that check and prints a warning; run `ci` for the released commit as soon as it can run again.

The executable in `dist/trrek.app` is stripped: its debug map and symbol table go to `dist/trrek.app.dSYM`, which stays on the build Mac (a release keeps a copy as `dist/release/trrek-vX.Y.Z.dSYM`) and symbolicates crash reports of that build.

## Make targets

| Target | Description |
| --- | --- |
| `make build` | Release build for arm64 |
| `make test` | Run the test suite |
| `make format` | Format the sources |
| `make lint` | Check formatting and lint rules |
| `make check` | Run tests and lint |
| `make hooks` | Install local git hooks |
| `make app` | Package `dist/trrek.app` (version from `Version.swift` unless `VERSION=X.Y.Z` is given) |
| `make install` | Install into `~/Applications` |
| `make release` | Signed, notarized release published to GitHub (`VERSION=X.Y.Z`) |
| `make perf` | Idle check: fails above 15 MB physical footprint or 1% CPU |
| `make clean` | Remove build output |

## Engine

`TrrekEngine` turns raw multitouch frames into commands and has no system dependencies. A single finger that lands in an edge strip and moves along it starts a slide: each edge runs its configured action (a level, app, tab or desktop switching, video scrubbing, media, zoom or undo), one step per fixed distance of travel. A second finger cancels the slide, lifting commits it, and a finger that disappears briefly can return and continue. A quick double tap on a corner fires that corner's action, a double tap on a media edge plays or pauses, and an optional three-finger tap sends a middle click. Before any of this, contacts larger than a fingertip are dropped as palms, no new gesture starts shortly after a key press or while a required hold key is up, and a paused engine ignores every frame. All distances and timings live in `Thresholds`. Run the engine tests with `make test`: on hosts with only the Command Line Tools it passes the testing macro plugin path that a plain `swift test` can miss.

## Performance

Measured with `make perf` after 30 s idle: 0.0 % CPU (`ps` reports a lifetime average) and a physical footprint of about 13 MB (budget: 15 MB and 1 % CPU). The footprint is `phys_footprint` rather than RSS, which also counts shared system framework pages. A manual test checklist is in [`docs/testing.md`](testing.md).
