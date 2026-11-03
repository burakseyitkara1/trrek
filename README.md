# trrek

A menu bar app for macOS that turns trackpad edges into single-finger controls for volume, brightness, keyboard backlight, app switching and media.

## Requirements

- macOS 26 or later
- Apple Silicon

## Make targets

| Target | Description |
| --- | --- |
| `make build` | Release build for arm64 |
| `make test` | Run the test suite |
| `make format` | Format the sources |
| `make lint` | Check formatting and lint rules |
| `make check` | Run tests and lint |
| `make hooks` | Install local git hooks |
| `make clean` | Remove build output |

## Engine

`TrrekEngine` turns raw multitouch frames into commands and has no system dependencies. A single finger that lands in an edge strip and moves along it starts a slide: the right edge steps volume, the left edge brightness, and the top and bottom edges run their configured action (app switching, video scrubbing, keyboard backlight or media), one step per fixed distance of travel. A second finger cancels the slide, lifting commits it, and a finger that disappears briefly can return and continue. A quick double tap on a corner mutes or takes a screenshot, a double tap on a media edge plays or pauses, and an optional three-finger tap sends a middle click. Before any of this, contacts larger than a fingertip are dropped as palms, no new gesture starts shortly after a key press or while a required hold key is up, and a paused engine ignores every frame. All distances and timings live in `Thresholds`. Run the engine tests with `swift test` (or `make test`).

## Development

The project is a Swift Package Manager package without an Xcode project. Install the tools with `brew install swiftlint swiftformat`, run `make hooks` once, and run `make check` before every push. Direct pushes to `main` are blocked; changes arrive through pull requests.
