# trrek

A menu bar app for macOS that turns trackpad edges into single-finger controls for volume, brightness, keyboard backlight, app switching, video scrubbing and media.

## Features

- Right edge controls volume, left edge brightness; the top and bottom edges run a configurable action (app switching, video scrubbing, keyboard backlight, media)
- Scrub Video: a slide on the top or bottom edge sends ← and → to the front app; most video players and browsers step 5 s per key
- External Monitor Brightness setting: on an external display that supports DDC/CI, the brightness edge sets the display's own brightness (best effort; some displays and connections do not answer). The brightness edge follows the screen with the pointer; the built-in display and displays without DDC/CI use the system brightness keys
- Corner double taps mute or take a screenshot; a double tap on a media edge plays or pauses
- Optional three-finger tap sends a middle click
- Precision Control setting: each step changes the level by a quarter as much (sent as an Option+Shift step)
- Freeze Cursor setting: the pointer stays still and scrolling is suppressed while sliding
- Palm, typing, hold-key and per-app pause gates
- Haptic feedback, and a level overlay for the keyboard backlight, external monitor brightness and the scrub distance, on the screen with the pointer (volume and built-in brightness use the system indicator)
- Only trackpads drive gestures; touches on a mouse with a touch surface are ignored
- Liquid Glass settings window, launch at login
- Export and import settings as a `.trrek` file; double-clicking a `.trrek` file in Finder offers to import it

## Requirements

- macOS 26 or later
- Apple Silicon

## Install

Run `make install` to build and copy `trrek.app` to `~/Applications`. A build installed with `make install` is not quarantined and opens normally. Released builds (0.1.1 and later) are signed with Developer ID and notarized by Apple: open the DMG, drag trrek onto the Applications shortcut and open it; macOS only asks once to confirm opening an app downloaded from the internet. (The 0.1.0 download was not notarized and had to be allowed in System Settings › Privacy & Security › Open Anyway.) On first launch trrek asks for the Accessibility permission: grant it in System Settings › Privacy & Security › Accessibility. Without it only the keyboard backlight edge works, since macOS does not deliver the events trrek posts for everything else; until it is granted, trrek shows the welcome window again at each launch and a dot on its menu bar icon.

### Keeping Accessibility permission across updates

macOS ties the Accessibility grant to the app's code signature. `scripts/build-app.sh` signs with the first identity it finds: `$TRREK_SIGN_IDENTITY`, a "Developer ID Application" identity, the self-signed "trrek Local Signing" identity created by `scripts/make-signing-identity.sh`, and only then ad-hoc. With a Developer ID identity, local builds and released builds share one grant, which survives every update. Ad-hoc builds change their code hash on every build, so the grant is lost after each reinstall. The first build signed with an identity shows a one-time keychain prompt asking to let `codesign` use the key: choose Always Allow. When you switch identities (for example from ad-hoc or the local identity to Developer ID), macOS keeps the old grant tied to the old signature: quit trrek, run `tccutil reset Accessibility com.burakseyitkara.trrek`, reopen it and grant access once more.

### Publishing a release

Releases are built, signed with Developer ID and the hardened runtime, notarized, stapled and published from the release Mac with `make release VERSION=X.Y.Z` (`scripts/release.sh`; update `Sources/TrrekEngine/Version.swift` and the changelog first, from an up-to-date `main`). One-time setup: create an app-specific password for your Apple ID and store the notarization credentials in the login keychain with `xcrun notarytool store-credentials trrek --team-id <TEAM_ID>`. `scripts/release.sh --version X.Y.Z --no-publish` produces the notarized DMG and zip in `dist/release` without tagging. The tag-triggered workflow only checks that the tagged commit builds and passes the tests.

## Usage

Put one finger in an edge strip of the trackpad and move along it.

- Right edge: volume. Left edge: brightness.
- Top and bottom edges: the action set in Settings (Switch Apps, Scrub Video, Keyboard Backlight, Media or Off). Scrub Video sends nothing while a trrek window is in front.
- Corners: double tap for the action set per corner (Mute, Screenshot or Off).
- A second finger cancels a slide; lifting commits it.

Open Settings from the menu bar icon, or by opening trrek again while it runs. General covers haptics, Precision Control, Freeze Cursor, launch at login, Export Settings…/Import Settings… and Reset to Defaults. Edges covers the top and bottom actions, strip width, Bottom Quarter Only (side edges respond only in their lower quarter) and External Monitor Brightness (DDC/CI; shown as not available when this Mac lacks the system support it needs). Corners & Taps covers the corner actions and middle click. Advanced covers the Hold-to-Slide key and mode, paused apps and the Accessibility status.

### Moving settings to another Mac

Export Settings… in the General tab saves every setting except Launch at Login to a `.trrek` file (indented JSON). Import Settings…, or double-clicking the file in Finder, asks before replacing the current settings; Launch at Login keeps its current value. A file that is damaged, not a trrek settings file or exported by a newer trrek is refused with an explanation, and the settings stay as they were.

## Performance

Measured with `make perf` on the installed 0.1.0 build after 30 s idle: 0.0 % CPU (`ps` reports a lifetime average) and a 12.8 MB physical footprint (budget: 15 MB and 1 % CPU). The footprint is `phys_footprint` rather than RSS, which also counts shared system framework pages. A manual test checklist is in `docs/testing.md`.

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

`TrrekEngine` turns raw multitouch frames into commands and has no system dependencies. A single finger that lands in an edge strip and moves along it starts a slide: the right edge steps volume, the left edge brightness, and the top and bottom edges run their configured action (app switching, video scrubbing, keyboard backlight or media), one step per fixed distance of travel. A second finger cancels the slide, lifting commits it, and a finger that disappears briefly can return and continue. A quick double tap on a corner mutes or takes a screenshot, a double tap on a media edge plays or pauses, and an optional three-finger tap sends a middle click. Before any of this, contacts larger than a fingertip are dropped as palms, no new gesture starts shortly after a key press or while a required hold key is up, and a paused engine ignores every frame. All distances and timings live in `Thresholds`. Run the engine tests with `make test`: on hosts with only the Command Line Tools it passes the testing macro plugin path that a plain `swift test` can miss.

## Development

The project is a Swift Package Manager package without an Xcode project. Install the tools with `brew install swiftlint swiftformat`, run `make hooks` once, and run `make check` before every push. Direct pushes to `main` are blocked; changes arrive through pull requests.
