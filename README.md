# trrek

A menu bar app for macOS that turns trackpad edges into single-finger controls for volume, brightness, keyboard backlight, app switching and media.

## Features

- Right edge controls volume, left edge brightness; the top and bottom edges run a configurable action (app switching, keyboard backlight, media)
- Corner double taps mute or take a screenshot; a double tap on a media edge plays or pauses
- Optional three-finger tap sends a middle click
- Precision steps with Option+Shift, cursor freeze and scroll suppression while sliding
- Palm, typing, hold-key and per-app pause gates
- Haptic feedback and a level overlay
- Liquid Glass settings window, launch at login

## Requirements

- macOS 26 or later
- Apple Silicon

## Install

Run `make install` to build and copy `trrek.app` to `~/Applications`. A build installed with `make install` is not quarantined and opens normally. A downloaded build is not notarized and macOS will block it on first launch: move it to Applications, try to open it once, then allow it in System Settings › Privacy & Security › Open Anyway (right-click › Open no longer bypasses Gatekeeper). On first launch trrek asks for the Accessibility permission: grant it in System Settings › Privacy & Security › Accessibility.

### Keeping Accessibility permission across updates

Every ad-hoc-signed build has a different code hash, so macOS drops the Accessibility grant after each reinstall. To avoid that, run `scripts/make-signing-identity.sh` once by hand; it creates a self-signed certificate named "trrek Local Signing" in your login keychain (macOS may ask for your password). `scripts/build-app.sh` then signs with it automatically. To use another identity, set `TRREK_SIGN_IDENTITY` to its name.

## Usage

Put one finger in an edge strip of the trackpad and move along it.

- Right edge: volume. Left edge: brightness.
- Top and bottom edges: the action set in Settings (Switch Apps, Keyboard Backlight, Media or Off).
- Corners: double tap for the action set per corner (Mute, Screenshot or Off).
- A second finger cancels a slide; lifting commits it.

Open Settings from the menu bar icon. General covers haptics, Precision Control, Freeze Cursor, launch at login and Reset to Defaults. Edges covers the top and bottom actions, strip width and Bottom Quarter Only (side edges respond only in their lower quarter). Corners & Taps covers the corner actions and middle click. Advanced covers the Hold-to-Slide key and mode, paused apps and the Accessibility status.

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
| `make app` | Package `dist/trrek.app` |
| `make install` | Install into `~/Applications` |
| `make perf` | Idle check: fails above 15 MB physical footprint or 1% CPU |
| `make clean` | Remove build output |

## Engine

`TrrekEngine` turns raw multitouch frames into commands and has no system dependencies. A single finger that lands in an edge strip and moves along it starts a slide: the right edge steps volume, the left edge brightness, and the top and bottom edges run their configured action (app switching, video scrubbing, keyboard backlight or media), one step per fixed distance of travel. A second finger cancels the slide, lifting commits it, and a finger that disappears briefly can return and continue. A quick double tap on a corner mutes or takes a screenshot, a double tap on a media edge plays or pauses, and an optional three-finger tap sends a middle click. Before any of this, contacts larger than a fingertip are dropped as palms, no new gesture starts shortly after a key press or while a required hold key is up, and a paused engine ignores every frame. All distances and timings live in `Thresholds`. Run the engine tests with `make test`: on hosts with only the Command Line Tools it passes the testing macro plugin path that a plain `swift test` can miss.

## Development

The project is a Swift Package Manager package without an Xcode project. Install the tools with `brew install swiftlint swiftformat`, run `make hooks` once, and run `make check` before every push. Direct pushes to `main` are blocked; changes arrive through pull requests.
