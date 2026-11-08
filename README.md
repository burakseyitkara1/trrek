# trrek

A menu bar app for macOS that turns trackpad edges into single-finger controls for volume, brightness, keyboard backlight, app, tab and desktop switching, zoom, undo, video scrubbing and media.

## Features

- Every edge runs the action you pick: volume, brightness, keyboard backlight, app switching, tab switching, desktop switching, video scrubbing, media, zoom, undo and redo, or off. By default the right edge controls volume, the left edge brightness, the top edge switches apps and the bottom edge sets the keyboard backlight
- Forward is rightward on the top and bottom edges and upward on the side edges: the next app, tab or desktop, zoom in, redo
- Scrub Video: a slide sends ← and → to the front app; most video players and browsers step 5 s per key
- Switch Tabs sends ⌃⇥ and ⌃⇧⇥, Zoom ⌘= and ⌘−, Undo & Redo ⌘Z and ⇧⌘Z to the front app; Switch Desktops sends ⌃← and ⌃→
- Slide Sensitivity setting: how far a finger slides for each step, from Very Low to Very High
- External Monitor Brightness setting: on an external display that supports DDC/CI, the brightness edge sets the display's own brightness (best effort; some displays and connections do not answer). The brightness edge follows the screen with the pointer; the built-in display and displays without DDC/CI use the system brightness keys
- Corner double taps: Mute, Screenshot, Screenshot Area, Play/Pause, Mission Control, App Windows, Show Desktop, Spotlight or Lock Screen. Mission Control, App Windows and Show Desktop open the system Mission Control app, so they work whatever its keyboard shortcuts are; a double tap on a media edge plays or pauses
- Optional three-finger tap sends a middle click
- Precision Control setting: each step changes the level by a quarter as much (sent as an Option+Shift step)
- Freeze Cursor setting: the pointer stays still and scrolling is suppressed while sliding
- Palm, typing, hold-key and per-app pause gates
- Haptic feedback, and a level overlay for the keyboard backlight, external monitor brightness and the scrub distance, on the screen with the pointer (volume and built-in brightness use the system indicator)
- Only trackpads drive gestures; touches on a mouse with a touch surface are ignored
- Liquid Glass settings window, launch at login
- Export and import settings as a `.trrek` file; double-clicking a `.trrek` file in Finder offers to import it
- English and Turkish interface: the Language setting follows the system or picks one of them
- Updates in the menu bar: an arrow on the icon when a newer version is published; one click in the menu downloads it with live progress, verifies it, replaces trrek in place and relaunches

## Requirements

- macOS 26 or later
- Apple Silicon

## Install

Run `make install` to build and copy `trrek.app` to `~/Applications`. A build installed with `make install` is not quarantined and opens normally. Released builds (0.1.1 and later) are signed with Developer ID and notarized by Apple: open the DMG, drag trrek onto the Applications shortcut and open it; macOS only asks once to confirm opening an app downloaded from the internet. (The 0.1.0 download was not notarized and had to be allowed in System Settings › Privacy & Security › Open Anyway.) On first launch trrek asks for the Accessibility permission: grant it in System Settings › Privacy & Security › Accessibility. Without it only the keyboard backlight edge works, since macOS does not deliver the events trrek posts for everything else; until it is granted, trrek shows the welcome window again at each launch and a dot on its menu bar icon.

### Keeping Accessibility permission across updates

macOS ties the Accessibility grant to the app's code signature. `scripts/build-app.sh` signs with the first identity it finds: `$TRREK_SIGN_IDENTITY`, a "Developer ID Application" identity, the self-signed "trrek Local Signing" identity created by `scripts/make-signing-identity.sh`, and only then ad-hoc. With a Developer ID identity, local builds and released builds share one grant, which survives every update. Ad-hoc builds change their code hash on every build, so the grant is lost after each reinstall. The first build signed with an identity shows a one-time keychain prompt asking to let `codesign` use the key: choose Always Allow. When you switch identities (for example from ad-hoc or the local identity to Developer ID), macOS keeps the old grant tied to the old signature: quit trrek, run `tccutil reset Accessibility com.burakseyitkara.trrek`, reopen it and grant access once more.

### Publishing a release

Releases are built, signed with Developer ID and the hardened runtime, notarized, stapled and published from the release Mac with `make release VERSION=X.Y.Z` (`scripts/release.sh`; update `Sources/TrrekEngine/Version.swift` and the changelog first, from an up-to-date `main`). One-time setup: create an app-specific password for your Apple ID and store the notarization credentials in the login keychain with `xcrun notarytool store-credentials trrek --team-id <TEAM_ID>`. The release notes are the version's `CHANGELOG.md` section; the script stops before building when that section is missing. While `MIRROR_REPO` in the script is set, it also publishes the same DMG, zip and notes to `burakseyitkara1/trrek-releases`, which versions 0.4.0 and 0.4.1 read for updates. `scripts/release.sh --version X.Y.Z --no-publish` produces the notarized DMG and zip in `dist/release` without tagging or publishing anywhere. The tag-triggered workflow only checks that the tagged commit builds and passes the tests.

Publishing requires a successful run of the `ci` workflow for the exact commit being released. Pull request runs test a merge of the branch, not the squashed commit on `main`, so start one on `main` and wait for it to pass before releasing: `gh workflow run ci --ref main`. When GitHub Actions cannot run at all, `scripts/release.sh --version X.Y.Z --allow-missing-ci` publishes without that check and prints a warning; run `ci` for the released commit as soon as it can run again.

The executable in `dist/trrek.app` is stripped: its debug map and symbol table go to `dist/trrek.app.dSYM`, which stays on the build Mac (a release keeps a copy as `dist/release/trrek-vX.Y.Z.dSYM`) and symbolicates crash reports of that build.

## Usage

Put one finger in an edge strip of the trackpad and move along it.

- Each edge runs the action set in Settings: Volume, Brightness, Keyboard Backlight, Switch Apps, Switch Tabs, Switch Desktops, Scrub Video, Media, Zoom, Undo & Redo or Off. By default the right edge is volume, the left edge brightness, the top edge Switch Apps and the bottom edge Keyboard Backlight (Media on a Mac without keyboard backlight support).
- Slide right on the top or bottom edge, or up on a side edge, to go forward. Switch Apps holds the app switcher open until you lift. Scrub Video, Switch Tabs, Zoom and Undo & Redo send nothing while a trrek window is in front.
- Corners: double tap for the action set per corner (Mute, Screenshot, Play/Pause, Mission Control, App Windows, Show Desktop, Spotlight, Lock Screen, Screenshot Area or Off). A corner keeps its action when one or both of its edges are Off.
- A second finger cancels a slide; lifting commits it.

Open Settings from the menu bar icon, or by opening trrek again while it runs. General covers haptics, Slide Sensitivity, Precision Control, Freeze Cursor, launch at login, Language, update checks, Export Settings…/Import Settings… and Reset to Defaults. Edges covers the action of each edge, strip width, Bottom Quarter Only (side edges respond only in their lower quarter) and External Monitor Brightness (DDC/CI; shown as not available when this Mac lacks the system support it needs). Corners & Taps covers the corner actions and middle click. Advanced covers the Hold-to-Slide key and mode, paused apps and the Accessibility status.

### Language

trrek's interface is in English and Turkish. The Language setting in General is System by default: trrek uses the first of the languages set in System Settings › General › Language & Region that it has, and English otherwise. Choosing English or Türkçe sets trrek's own language preference (`AppleLanguages` in its defaults); System removes it. Choosing trrek's language in System Settings › General › Language & Region › Applications works too: trrek's Language setting follows that choice at the next launch. The new language applies after a relaunch, which the Relaunch button next to the setting offers whenever the choice shows a different language from the one on screen. The language belongs to this Mac's user: it is not part of an exported `.trrek` file, an import keeps it, and so does Reset to Defaults.

### Moving settings to another Mac

Export Settings… in the General tab saves every setting except Launch at Login and the language to a `.trrek` file (indented JSON). Import Settings…, or double-clicking the file in Finder, asks before replacing the current settings; Launch at Login and the language keep their current values. A file that is damaged, not a trrek settings file or exported by a newer trrek is refused with an explanation, and the settings stay as they were.

### Updates

trrek looks for a newer version among the releases of this repository on GitHub (versions 0.4.0 and 0.4.1 read the releases-only `burakseyitkara1/trrek-releases` repository, which receives the same releases until those installs have updated). With Check for Updates Automatically on (General; the default) it checks at most once a day, about 10 seconds after launch, about 10 seconds after the Mac wakes or when the menu opens; after a failed check it waits an hour before trying again. Check for Updates… in the menu and Check Now in General check at any time; they show an alert only when trrek is up to date or the check failed. Each check is one HTTPS request to the releases API that sends only trrek's version as the user agent: no cookies, no identifiers, no settings (the server sees your IP address, as with any request). trrek posts no notifications.

When a newer version is found, the menu bar icon shows a small arrow in its top-left corner and the menu shows Update Available: trrek X.Y.Z at the top (General shows the same with an Update Now button). Choosing it keeps the menu open: the row turns into Downloading trrek X.Y.Z… with a progress bar, then Installing trrek X.Y.Z…, and trrek quits and opens the new version. The disk image goes to trrek's own caches folder (`~/Library/Caches/com.burakseyitkara.trrek/Updates`), never to Downloads, and is deleted after the install (and at the next launch, if one was left). trrek only downloads from that repository's own release address for the version it found.

Before anything is installed, trrek checks that the disk image is signed with trrek's Developer ID, mounts it read-only and out of sight, copies the new app to a temporary folder and ejects the image, then checks the copy: it must be signed with trrek's Developer ID, notarized, and carry trrek's bundle identifier and exactly the version that was found, newer than the running one. It checks the copy again right before replacing the app where it is, and checks the installed app once more (putting the previous app back if that fails). Because every release is signed with the same Developer ID, the new version keeps the Accessibility permission. If the download or a check fails, the row says Update Failed — Try Again and choosing it starts over. When trrek can't replace itself — it runs from a disk image, a read-only volume or a temporary location macOS uses for apps opened straight from Downloads, or it can't write to its folder — or the disk image can't be read, trrek opens the release page in the browser and the row says Update in Browser…. Turn Check for Updates Automatically off to make no requests unless you ask; the setting is part of an exported `.trrek` file. `--assume-version X.Y.Z` makes the check treat the running version as X.Y.Z, to try the flow against the real releases; it keeps its check state apart from the normal one. Whatever version it assumes, trrek never installs a version older than the one actually running.

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

`TrrekEngine` turns raw multitouch frames into commands and has no system dependencies. A single finger that lands in an edge strip and moves along it starts a slide: each edge runs its configured action (a level, app, tab or desktop switching, video scrubbing, media, zoom or undo), one step per fixed distance of travel. A second finger cancels the slide, lifting commits it, and a finger that disappears briefly can return and continue. A quick double tap on a corner fires that corner's action, a double tap on a media edge plays or pauses, and an optional three-finger tap sends a middle click. Before any of this, contacts larger than a fingertip are dropped as palms, no new gesture starts shortly after a key press or while a required hold key is up, and a paused engine ignores every frame. All distances and timings live in `Thresholds`. Run the engine tests with `make test`: on hosts with only the Command Line Tools it passes the testing macro plugin path that a plain `swift test` can miss.

## Building from source

You need macOS 26 on Apple silicon and the Xcode command line tools (`xcode-select --install`); Xcode itself is not required. Clone the repository and run:

```sh
make install
```

This builds the app, signs it and copies it to `~/Applications/trrek.app`. Without a Developer ID certificate the build is signed ad hoc, so macOS asks for the Accessibility permission again after every rebuild; `scripts/make-signing-identity.sh` creates a local signing identity that keeps the grant (see "Keeping Accessibility permission across updates"). Run the tests with `make test`.

## How trrek reads the trackpad

macOS has no public interface that delivers raw trackpad touches to a background app, nor one that sets the keyboard backlight or an external display's brightness. trrek therefore uses a few private system frameworks for multitouch frames and haptics, keyboard backlight, built-in display brightness and DDC/CI. Every private symbol is looked up at run time in one file, `Sources/TrrekPlatform/PrivateSymbols.swift`; when a symbol is missing, the feature that needs it turns off and the rest keeps working. trrek is not sandboxed and is not distributed through the App Store. A future macOS release may change these interfaces.

## Development

The project is a Swift Package Manager package without an Xcode project. Install the tools with `brew install swiftlint swiftformat`, run `make hooks` once, and run `make check` before every push. Changes arrive through pull requests to `main`. See [CONTRIBUTING.md](CONTRIBUTING.md).

To report a security vulnerability, see [SECURITY.md](SECURITY.md).

## License

trrek is released under the [MIT License](LICENSE).
