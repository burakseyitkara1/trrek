# trrek Foundation, CI/CD, Spike and Gesture Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An SPM package that builds and is tested in CI, app packaging and a release pipeline, the `TrrekProbe` tool that verifies the private API assumptions, and `TrrekEngine`, which proves every gesture rule in the spec with tests.

**Architecture:** A three-layer SPM package (Engine → Platform → App). This plan sets up the Engine completely, the symbol loading and raw data layer of the Platform, the packaging scripts and CI/CD. The app layer (menu, settings window) and the remaining Platform bridges come in the next plan.

**Tech Stack:** Swift 6 (tools 6.0), Swift Testing, AppKit/CoreGraphics/IOKit, private MultitouchSupport (dlsym), GitHub Actions (`macos-26`), SwiftLint, SwiftFormat, Makefile.

**Spec:** `docs/superpowers/specs/2026-11-03-trrek-design.md`

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 language mode, platform `.macOS("26.0")`, arm64 only; no Swift 6.3+ language features and no macOS 27 APIs.
- No external package dependencies. Private frameworks are not linked; they are resolved at run time with `dlopen`/`dlsym` only inside `Sources/TrrekPlatform/PrivateSymbols.swift`.
- No other app, library or project name appears in the project; no attribution is written; no code is copied from outside code.
- Code, comments, commit messages and UI texts are in English; documents and PR bodies are in Turkish. The app name is `trrek` everywhere; bundle ID `com.burakseyitkara.trrek`.
- Performance budget: 0% CPU at idle, memory under 15 MB; the Engine does no heap allocation per frame; no periodic timers.
- Each task on its own branch (`feat/`, `ci/`, `chore/`, `test/`), with a PR, after `make check` passes locally; squash merge.
- The threshold values are the initial values in spec 5.2 and live in one place in `Thresholds`.

## Review Focus

1. A device whose surface size comes as 0 or negative: no zone must be detected, no crash (Task 4 test `zeroGeometryYieldsNoZone`).
2. A frame with more than 16 touches: `TouchBuffer.append` returns `false`, the excess is silently dropped (Task 4 test `bufferRejectsSeventeenthTouch`).
3. A frame whose timestamp goes backwards (device restart): durations must not be negative; `tick(now:)` must not produce a commit with a past `now` (Task 5 test `backwardsTimestampDoesNotCommit`).
4. A new touch with the same `id` after the `lost` time has expired: it must be a new candidate, not a continuation of the old slide (Task 5 test `reusedIDAfterLostExpiryStartsFresh`).
5. When `update(config:)` or `reset()` is called in the `spent`/`threeFinger` states, `freezeCursor(false)` must be sent only if it is actually on (Task 7 test `resetEmitsFreezeOffOnlyWhenFrozen`).

---

### Task 1: Package skeleton and local toolchain

**Files:**
- Create: `Package.swift`, `Makefile`, `.swiftlint.yml`, `.swiftformat`, `LICENSE`, `README.md`, `CHANGELOG.md`, `scripts/install-hooks.sh`
- Create: `Sources/TrrekEngine/Version.swift`, `Sources/TrrekPlatform/PrivateSymbols.swift`, `Sources/Trrek/main.swift`, `Sources/TrrekProbe/main.swift`, `Tests/TrrekEngineTests/VersionTests.swift`
- Modify: `.gitignore` (add: `dist/`, `*.icns`, `*.iconset/`)

**Interfaces:**
- Produces: `public enum TrrekVersion { public static let string: String }` (TrrekEngine); target names `TrrekEngine`, `TrrekPlatform`, `Trrek`, `TrrekProbe`, `TrrekEngineTests`; `make build|test|lint|format|check|hooks|clean`.

- [ ] **Step 1: Install the local tools**

Run: `brew list swiftlint swiftformat >/dev/null 2>&1 || brew install swiftlint swiftformat`
Expected: `swiftlint version` and `swiftformat --version` print output.

- [ ] **Step 2: Write the failing test** — `Tests/TrrekEngineTests/VersionTests.swift`

```swift
import Testing
@testable import TrrekEngine

@Test func versionStringIsSemver() {
    let parts = TrrekVersion.string.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
```

- [ ] **Step 3: Write the package definition** — `Package.swift`: tools 6.0; `platforms: [.macOS("26.0")]`; targets: `TrrekEngine` (target), `TrrekPlatform` (target, dependencies: TrrekEngine, linkerSettings: `.linkedFramework("AppKit")`, `.linkedFramework("IOKit")`, `.linkedFramework("CoreGraphics")`), `Trrek` (executableTarget, dependencies: TrrekPlatform), `TrrekProbe` (executableTarget, dependencies: TrrekPlatform), `TrrekEngineTests` (testTarget, dependencies: TrrekEngine). `swiftSettings: [.swiftLanguageMode(.v6)]` on all targets.

- [ ] **Step 4: Write the stub files** — `Version.swift`: `public enum TrrekVersion { public static let string = "0.0.0" }`. `PrivateSymbols.swift`: `enum PrivateSymbols {}` (empty). `Trrek/main.swift`: `import AppKit` + `print("trrek \(TrrekVersion.string)")` (temporary). `TrrekProbe/main.swift`: `print("trrek-probe: no commands yet")`.

- [ ] **Step 5: Run the test**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 1 test passed`

- [ ] **Step 6: Lint and format configuration** — `.swiftformat`: `--swiftversion 6.0`, `--indent 4`, `--maxwidth 120`, `--exclude .build,dist`. `.swiftlint.yml`: `excluded: [.build, dist]`, `line_length: {warning: 120, error: 160}`, `disabled_rules: [todo]`, `opt_in_rules: [empty_count, closure_spacing]`, `identifier_name: {min_length: 2, excluded: [x, y, id, dx, dy, t, e]}`.

- [ ] **Step 7: Makefile** — targets: `build` (`swift build -c release --arch arm64`), `test` (`swift test`), `format` (`swiftformat .`), `lint` (`swiftformat --lint . && swiftlint lint --strict`), `check` (`test lint`), `hooks` (`scripts/install-hooks.sh`), `clean` (`rm -rf .build dist`). All in `.PHONY`.

- [ ] **Step 8: Hook script** — `scripts/install-hooks.sh`: writes `.git/hooks/pre-push` (if one of the ref lines on stdin goes to `refs/heads/main`, `echo "direct push to main is blocked; open a PR"` and `exit 1`) and `.git/hooks/pre-commit` (`make lint`), `chmod +x`. Run: `make hooks`.

- [ ] **Step 9: Project files** — `LICENSE` MIT (Copyright 2026 Burak Seyit Kara). `README.md`: name, one sentence, requirements (macOS 26+, Apple Silicon), `make` targets, a "Development" section. `CHANGELOG.md`: a short description header and under `## [Unreleased]` `- Project scaffold: SPM package, Makefile, lint/format config, git hooks`.

- [ ] **Step 10: Full check**

Run: `make check`
Expected: tests pass, `swiftformat --lint` and `swiftlint` with zero warnings.

- [ ] **Step 11: Commit and PR**

```bash
git add -A && git commit -m "chore: scaffold SPM package, Makefile, lint config and git hooks"
```
Branch `chore/scaffold`, same PR title; there is no CI yet, merge after review.

---

### Task 2: Packaging scripts and CI/CD

**Files:**
- Create: `Resources/Info.plist.in`, `scripts/build-app.sh`, `scripts/render-icon.swift`, `scripts/make-icon.sh`, `scripts/perf.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/dependabot.yml`, `.github/PULL_REQUEST_TEMPLATE.md`
- Modify: `Makefile` (add: `app`, `install`, `icon`, `perf`), `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 1 target names.
- Produces: `scripts/build-app.sh [--version X.Y.Z] [--build N]` → `dist/trrek.app`; `make app`, `make install`; CI workflow name `ci`, job name `build-test`.

- [ ] **Step 1: Info.plist template** — keys: `CFBundleIdentifier=com.burakseyitkara.trrek`, `CFBundleName=trrek`, `CFBundleDisplayName=trrek`, `CFBundleExecutable=trrek`, `CFBundlePackageType=APPL`, `CFBundleShortVersionString=${VERSION}`, `CFBundleVersion=${BUILD}`, `CFBundleIconFile=AppIcon`, `LSMinimumSystemVersion=26.0`, `LSUIElement=true`, `NSHumanReadableCopyright=Copyright © 2026 Burak Seyit Kara`, `NSPrincipalClass=NSApplication`.

- [ ] **Step 2: Icon generation** — `scripts/render-icon.swift` (`swift scripts/render-icon.swift <out.png>`): 1024×1024 with CoreGraphics, a rounded-square dark background, a light gray rounded trackpad silhouette in the middle, a bright blue vertical strip on its right edge. `scripts/make-icon.sh <out.icns>`: PNG → sizes 16…1024 into `trrek.iconset/` with `sips` → `iconutil -c icns`.

- [ ] **Step 3: build-app.sh** — arguments `--version` (default `0.0.0`), `--build` (default `1`); `swift build -c release --arch arm64 --product Trrek`; `dist/trrek.app/Contents/{MacOS,Resources}`; binary named `trrek`; `Info.plist.in` → `sed`; the `make-icon.sh` output into Resources; copy `Sources/Trrek/Resources/*` if present; `codesign --force --sign - --deep dist/trrek.app`; finally the `codesign -dv` output.

- [ ] **Step 4: Makefile additions** — `app` (`scripts/build-app.sh --version $(VERSION) --build $(BUILD)`, default `VERSION=0.0.0 BUILD=1`), `install` (`app` then `rm -rf ~/Applications/trrek.app && cp -R dist/trrek.app ~/Applications/ && lsregister -f ~/Applications/trrek.app`), `icon`, `perf` (`scripts/perf.sh`).

- [ ] **Step 5: perf.sh** — opens `~/Applications/trrek.app` or `dist/trrek.app`, waits 30 s, prints `ps -o %cpu=,rss= -p <pid>` and `footprint <pid>`, `exit 1` if RSS is above 15360 KB.

- [ ] **Step 6: Local verification**

Run: `make app && ls dist/trrek.app/Contents/MacOS && codesign -dv dist/trrek.app 2>&1 | head -3`
Expected: the `trrek` binary exists; `Signature=adhoc`.

- [ ] **Step 7: ci.yml** — per spec 10.3: `name: ci`; `on: pull_request: paths-ignore: ['docs/**', '**/*.md']`, `workflow_dispatch`; `concurrency` cancel; job `build-test`, `runs-on: macos-26`, `timeout-minutes: 20`; steps: `actions/checkout@v4`, `actions/cache@v4` (`path: .build`, `key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift','Package.resolved') }}`, `restore-keys: ${{ runner.os }}-swift-`), `swift build -c release --arch arm64`, `swift test`, `swiftformat --lint .`, `swiftlint lint --strict`, `scripts/build-app.sh --version 0.0.0 --build ${{ github.run_number }}`, `ditto -c -k --keepParent dist/trrek.app trrek-ci.zip`, `actions/upload-artifact@v4` (`name: trrek-app`, `retention-days: 7`).

- [ ] **Step 8: release.yml** — `on: push: tags: ['v*.*.*']`; `permissions: contents: write`; the same build/test; `TAG=${GITHUB_REF_NAME}`; `scripts/build-app.sh --version ${TAG#v} --build ${{ github.run_number }}`; `ditto -c -k --keepParent dist/trrek.app trrek-${TAG}.zip`; `hdiutil create -volname trrek -srcfolder dist/trrek.app -ov -format UDZO trrek-${TAG}.dmg`; `gh release create "$TAG" --generate-notes trrek-${TAG}.zip trrek-${TAG}.dmg` (`GH_TOKEN: ${{ github.token }}`).

- [ ] **Step 9: dependabot and PR template** — `dependabot.yml`: `package-ecosystem: github-actions`, `directory: /`, `schedule.interval: weekly`. `PULL_REQUEST_TEMPLATE.md` (Turkish): `## Özet`, `## Değişiklik türü` (Feature/Fix/CI/Docs/Test boxes), `## Test notları`, `## Kontrol listesi` (`make check` passed, relevant `docs/testing.md` items, no perf impact, CHANGELOG updated).

- [ ] **Step 10: Commit and PR**

```bash
git add -A && git commit -m "ci: add app packaging scripts, CI and release workflows"
```
Branch `ci/packaging-and-workflows`. After the PR is opened, `build-test` must be green with `gh pr checks --watch`; the `trrek-app` artifact must be listed.

---

### Task 3: Platform foundation and the TrrekProbe spike tool

**Files:**
- Create: `Sources/CMultitouch/include/cmultitouch.h`, `Sources/CMultitouch/cmultitouch.c`
- Create: `Sources/TrrekPlatform/PrivateSymbols.swift` (rewrite), `Sources/TrrekPlatform/Multitouch/MultitouchDevices.swift`, `Sources/TrrekPlatform/Multitouch/RawFrameStream.swift`, `Sources/TrrekPlatform/Haptics/ActuatorHaptics.swift`, `Sources/TrrekPlatform/Input/EventStamp.swift`, `Sources/TrrekPlatform/Input/MediaKeyPoster.swift`, `Sources/TrrekPlatform/Input/KeyPoster.swift`, `Sources/TrrekPlatform/Input/EventTapGuard.swift`, `Sources/TrrekPlatform/System/Permissions.swift`
- Create: `Sources/TrrekProbe/main.swift` (rewrite), `Sources/TrrekProbe/Commands.swift`
- Modify: `Package.swift` (target `CMultitouch`, add to the `TrrekPlatform` dependencies), `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 1 targets.
- Produces (used in the next plan):
  - C: `typedef struct { int32_t frame; double timestamp; int32_t identifier; int32_t state; int32_t fingerID; int32_t handID; float nx, ny, nvx, nvy; float total; float pressure; float angle; float majorAxis; float minorAxis; float ax, ay, avx, avy; int32_t reserved0, reserved1; float density; } MTTouch;` (`_Static_assert(sizeof(MTTouch) == 96, "MTTouch must be 96 bytes")`), `typedef void *MTDeviceRef;`, `typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch *, int32_t, double, int32_t);`
  - `enum PrivateSymbols` — `static let multitouch: MultitouchSymbols?`, `static let actuator: ActuatorSymbols?`; each struct holds the relevant `@convention(c)` function pointers.
  - `struct MultitouchDeviceInfo { let ref: MTDeviceRef; let isBuiltIn: Bool; let widthMM: Float; let heightMM: Float; let multitouchID: UInt64? }`
  - `enum MultitouchDevices { static func enumerate() -> [MultitouchDeviceInfo] }` (gets the surface size with `MTDeviceGetSensorSurfaceDimensions`, 1/100 mm → mm; `multitouchID` is matched from the `Multitouch ID` and `MT Built-In` properties of the IORegistry `AppleMultitouchDevice` entries)
  - `final class RawFrameStream { init(devices: [MultitouchDeviceInfo]); var onFrame: ((MTDeviceRef, UnsafeBufferPointer<MTTouch>, Double) -> Void)?; func start() throws; func stop() }` — the callback is on the framework thread; `onFrame` is assigned before `start()`.
  - `final class ActuatorHaptics { init?(multitouchID: UInt64); @discardableResult func actuate(waveform: Int32) -> Bool }`
  - `enum EventStamp { static let userData: Int64 = 0x7472726B; static let source: CGEventSource; static func isOurs(_ event: CGEvent) -> Bool }`
  - `enum MediaKey: Int32 { soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7, play = 16, next = 17, previous = 18, illuminationUp = 21, illuminationDown = 22 }`; `enum MediaKeyPoster { static func post(_ key: MediaKey, fine: Bool) }`
  - `enum KeyPoster { static func press(keyCode: CGKeyCode, flags: CGEventFlags); static func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags); static func modifierUp(_ keyCode: CGKeyCode) }`
  - `final class EventTapGuard { init(); var isAvailable: Bool; func setFreeze(_ on: Bool) }` (in this task only Tap B: swallowing mouseMoved/dragged/scrollWheel)
  - `enum Permissions { static var isTrusted: Bool; static func prompt() }`

- [ ] **Step 1: C header target** — `cmultitouch.h` the types above + `_Static_assert`; `cmultitouch.c` a single empty function (`void cmultitouch_anchor(void) {}`). Add `.target(name: "CMultitouch")` to `Package.swift` and the `TrrekPlatform` dependency.

- [ ] **Step 2: Build verification**

Run: `swift build 2>&1 | tail -3`
Expected: no errors (`_Static_assert` verifies the layout).

- [ ] **Step 3: PrivateSymbols** — `dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)`; `MultitouchSymbols` fields: `createList: @convention(c) () -> Unmanaged<CFArray>?`, `isBuiltIn: (MTDeviceRef) -> Bool`, `surfaceDimensions: (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32`, `registerFrameCallback: (MTDeviceRef, MTFrameCallback) -> Void`, `unregisterFrameCallback`, `start: (MTDeviceRef, Int32) -> Int32`, `stop: (MTDeviceRef) -> Int32`, `release: (MTDeviceRef) -> Void`. `ActuatorSymbols`: `createFromDeviceID: (UInt64) -> Unmanaged<CFTypeRef>?`, `open: (CFTypeRef) -> Int32`, `actuate: (CFTypeRef, Int32, UInt32, Float, Float) -> Int32`, `close: (CFTypeRef) -> Int32`. Each symbol with `dlsym`; if one is missing the struct is `nil`. Symbol names: `MTDeviceCreateList`, `MTDeviceIsBuiltIn`, `MTDeviceGetSensorSurfaceDimensions`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceRelease`, `MTActuatorCreateFromDeviceID`, `MTActuatorOpen`, `MTActuatorActuate`, `MTActuatorClose`.

- [ ] **Step 4: MultitouchDevices and RawFrameStream** — the signatures in the Interfaces block. Callback: at file level `private let frameCallback: MTFrameCallback = { dev, touches, count, ts, _ in RawFrameStream.current?.dispatch(dev, touches, count, ts) }`; `RawFrameStream.current` is a `nonisolated(unsafe) static weak var`. Multiple devices are supported.

- [ ] **Step 5: Haptics, event posting, tap, permission** — the signatures in the Interfaces block; `MediaKeyPoster.post` is `NSEvent.otherEvent` + `data1 = (key << 16) | (0x0A << 8)` / `0x0B` from spec 6.4; `fine` → `[.option, .shift]`; `KeyPoster` `CGEvent(keyboardEventSource: EventStamp.source, virtualKey:, keyDown:)`; `EventTapGuard` Tap B `.cgSessionEventTap/.headInsertEventTap/.defaultTap`, the callback returns `nil` (swallows) if the event is not `EventStamp.isOurs` and freeze is on, `tapDisabledByTimeout` → re-enable; `Permissions.isTrusted = AXIsProcessTrusted()`, `prompt()` → `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)`.

- [ ] **Step 6: TrrekProbe commands** — `trrek-probe <command>`: `devices` (each device: built-in, W×H mm, multitouch ID); `frames [seconds]` (on each frame: time, touch count, each touch `id state nx ny major minor`; exits when the time is up); `layout-check` (`OK` if, in the first 50 frames, `nx,ny ∈ [0,1]`, `majorAxis ∈ (0,100)`, `state ∈ 0...7`, otherwise `MISMATCH` and `exit 1`; `NO FRAMES` if there is no touch within 10 s); `haptic <id> [repeat]`; `key <soundUp|soundDown|brightnessUp|brightnessDown|mute|play|next|previous|illuminationUp|illuminationDown> [--fine]`; `switcher` (⌘ down, 500 ms, Tab, 500 ms, Tab, 500 ms, ⌘ up); `freeze <seconds>` (`EventTapGuard.setFreeze(true)`, wait, turn off); `mem` (its own RSS in MB with `task_info`). Help text with no arguments.

- [ ] **Step 7: Local verification**

Run: `swift build && .build/debug/TrrekProbe devices && .build/debug/TrrekProbe layout-check`
Expected: at least one device, `built-in=true`, reasonable mm sizes (e.g. around 120×80); `layout-check` → `OK` (a finger must be put on the trackpad).

- [ ] **Step 8: make check and commit**

```bash
make check && git add -A && git commit -m "feat(platform): add private symbol loader, raw multitouch stream and probe tool"
```
Branch `feat/platform-probe`. PR; CI green; review; merge.

---

### Task 3b: Spike results (the main session runs this)

**Files:**
- Create: `docs/superpowers/specs/2026-11-03-spike-results.md`
- Modify: spec 5.2 thresholds and 6.3/6.7 decisions (if needed)

- [ ] **Step 1:** Record the output of `TrrekProbe devices`, `layout-check`, `frames 5` (surface unit, whether a zero-touch frame arrives at lift-off).
- [ ] **Step 2:** `haptic 1..6` in order; record the Light/Medium/Strong mapping.
- [ ] **Step 3:** `key soundUp`, `key brightnessUp`, `key illuminationUp`, `key soundUp --fine`; right after each, take a screenshot with `screencapture -x` and record whether the HUD appears (the 6.7 Path A/B decision, item 11.4–5).
- [ ] **Step 4:** `switcher` (does the switcher open), `freeze 3` (does the cursor stop), `mem` (RSS).
- [ ] **Step 5:** Write the results document; if a threshold or decision changes, update the spec in the same PR. Branch `docs/spike-results`.

---

### Task 4: Engine types, configuration and geometry

**Files:**
- Create: `Sources/TrrekEngine/Types.swift`, `Sources/TrrekEngine/Config.swift`, `Sources/TrrekEngine/Commands.swift`, `Sources/TrrekEngine/Geometry.swift`
- Create: `Tests/TrrekEngineTests/Support/FrameBuilder.swift`, `Tests/TrrekEngineTests/Support/RecordingSink.swift`, `Tests/TrrekEngineTests/GeometryTests.swift`, `Tests/TrrekEngineTests/TouchBufferTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Produces (the types in spec 5.1, 5.2, 5.7, all `public`, `Sendable`, `Equatable`):
  - `struct Touch { var id: Int32; var x: Float; var y: Float; var majorAxisMM: Float; init(id:x:y:majorAxisMM:) }`
  - `struct TouchBuffer { static let capacity = 16; private(set) var count: Int; init(); @discardableResult mutating func append(_: Touch) -> Bool; subscript(_ i: Int) -> Touch; func contains(id: Int32) -> Bool; func touch(id: Int32) -> Touch? }` — storage `InlineArray<16, Touch>`.
  - `struct DeviceGeometry { var widthMM: Float; var heightMM: Float; var isBuiltIn: Bool; var isValid: Bool { widthMM > 0 && heightMM > 0 } }`
  - `struct Frame { var deviceID: UInt64; var timestamp: TimeInterval; var geometry: DeviceGeometry; var touches: TouchBuffer }`
  - `enum Edge: CaseIterable { left, right, top, bottom }`, `enum Corner: CaseIterable { topLeft, topRight, bottomLeft, bottomRight }`, `enum Zone { edge(Edge), corner(Corner), none }`
  - `enum EdgeAction: String, CaseIterable, Codable`, `enum CornerAction: String, CaseIterable, Codable` (spec 5.2)
  - `struct Thresholds { … the spec 5.2 fields and defaults; init() }`
  - `struct EngineConfig { left, right, top, bottom: EdgeAction; topLeft, topRight, bottomLeft, bottomRight: CornerAction; bottomQuarterOnly, precision, freezeCursor, middleClickEnabled, holdKeyRequired: Bool; thresholds: Thresholds; init(); func action(for: Edge) -> EdgeAction; func action(for: Corner) -> CornerAction }`
  - `enum HapticEvent { start, step, tap, limit }`, `enum GestureCommand` (spec 5.7), `protocol CommandSink: AnyObject { func handle(_ command: GestureCommand, device: UInt64) }`
  - `enum Geometry { static func zone(of: Touch, in: DeviceGeometry, config: EngineConfig) -> Zone; static func deltaMM(edge: Edge, from: Touch, to: Touch, in: DeviceGeometry) -> (along: Float, perpendicular: Float); static func stepMM(for: EdgeAction, thresholds: Thresholds) -> Float; static func edges(of: Corner) -> (vertical: Edge, horizontal: Edge) }`
  - Test helpers: `struct FrameBuilder { var geometry = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true); var deviceID: UInt64 = 1; func frame(t: TimeInterval, _ touches: [(id: Int32, xMM: Float, yMM: Float)], major: Float = 8) -> Frame }` (mm → normalize); `final class RecordingSink: CommandSink { var commands: [GestureCommand]; func count(_: GestureCommand) -> Int; func contains(_: GestureCommand) -> Bool }`.

- [ ] **Step 1: Failing tests** — `GeometryTests.swift`:

```swift
@Test func rightStripDetectedWithStandardWidth() {
    let g = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)
    let cfg = EngineConfig()
    #expect(Geometry.zone(of: Touch(id: 1, x: 115/120, y: 40/80, majorAxisMM: 8), in: g, config: cfg) == .edge(.right))
    #expect(Geometry.zone(of: Touch(id: 1, x: 100/120, y: 40/80, majorAxisMM: 8), in: g, config: cfg) == .none)
}
@Test func cornerIsIntersectionOfStrips() { /* x=115, y=5 → .corner(.bottomRight) */ }
@Test func offEdgeIsNotAZone() { /* cfg.top = .off; x=60, y=78 → .none */ }
@Test func bottomQuarterOnlyLimitsVerticalEdges() { /* bottomQuarterOnly; x=115,y=40 → .none; y=15 → .edge(.right) */ }
@Test func edgeWidthNarrowAndWide() { /* edgeWidthMM 7: x=112 → .none; 14: x=112 → .edge(.right) */ }
@Test func zeroGeometryYieldsNoZone() { /* widthMM 0 → .none */ }
@Test func deltaAlongVerticalEdgeIsPositiveUpward() { /* right edge, y 15→35 mm → along == 20, perpendicular == 0 */ }
@Test func stepDistancesFollowThresholds() { /* volume 3.75, switchApps 12, scrubVideo 6, media 20 */ }
```
`TouchBufferTests.swift`: `bufferRejectsSeventeenthTouch` (16 appends → true, the 17th → false, count 16), `bufferLookupByID`.

- [ ] **Step 2: Run the tests** — Run: `swift test 2>&1 | tail -3` — Expected: build error (types missing).

- [ ] **Step 3: Write the types, configuration, commands and geometry** — the signatures in the Interfaces block; `zone(of:)`: `.none` if the geometry is invalid; first the edge strips are computed (an edge with the `off` action does not count as a strip), `.corner` if two strips intersect, `.edge` if one, and for `bottomQuarterOnly` and a vertical edge, `.none` if `y ≥ 0.25`.

- [ ] **Step 4: Run the tests** — Run: `swift test 2>&1 | tail -3` — Expected: all tests pass.

- [ ] **Step 5: CHANGELOG** — `- Engine: core types, configuration, command model and edge/corner geometry`.

- [ ] **Step 6: Commit and PR** — `make check && git commit -am "feat(engine): add types, config, commands and geometry"`; branch `feat/engine-types`.

---

### Task 5: Slide state machine

**Files:**
- Create: `Sources/TrrekEngine/GestureEngine.swift`, `Sources/TrrekEngine/EngineState.swift`
- Create: `Tests/TrrekEngineTests/SlideTests.swift`, `Tests/TrrekEngineTests/Support/Drive.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 4 types.
- Produces: `public final class GestureEngine { init(config: EngineConfig, sink: CommandSink); func update(config: EngineConfig); func process(_ frame: Frame); func tick(now: TimeInterval); func noteKeyDown(at: TimeInterval); func setHoldKeySatisfied(_: Bool); func setPaused(_: Bool); func reset(); var stateKind: StateKind }`, `public enum StateKind { idle, candidate, sliding, lost, spent, threeFinger }`. The internal state is `enum EngineState` (with the data of spec 5.4). In this task the bodies of `noteKeyDown`, `setHoldKeySatisfied`, `setPaused` only assign fields (Task 7 completes them); the tap/three-finger transitions are in Task 6.
- Test helper: `extension GestureEngine { @discardableResult func drive(_ fb: FrameBuilder, id: Int32, from: (Float, Float), to: (Float, Float), stepMM: Float = 1, dt: TimeInterval = 0.008, startT: TimeInterval) -> TimeInterval }` — produces frames from `from` to `to` in `stepMM` steps, returns the last time.

- [ ] **Step 1: Failing tests** — `SlideTests.swift`:

```swift
@Test func sixteenStepsForSixtyMillimetres() {
    let sink = RecordingSink(); let e = GestureEngine(config: EngineConfig(), sink: sink); let fb = FrameBuilder()
    e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.haptic(.step)) == 16)
    #expect(sink.count(.haptic(.start)) == 1)
}
@Test func belowSlideStartNoCommands() { /* 115,15 → 115,17.5; no steps; stateKind == .candidate */ }
@Test func downwardSlideEmitsNegativeSteps() { /* 115,75 → 115,15 → 16 × stepVolume(-1) */ }
@Test func precisionSetsFineFlag() { /* cfg.precision = true → stepVolume(1, fine: true) */ }
@Test func perpendicularMoveAbortsCandidate() { /* 115,40 → 110,40 (5 mm perpendicular) → .spent; then 110,40 → 110,70 no commands */ }
@Test func secondFingerCancelsSlide() { /* id 2 is added in the middle of a slide → stateKind .spent, freezeCursor(false), then .idle when both fingers lift */ }
@Test func lostFingerReturnsWithinTimeoutContinues() { /* 20 mm slide; empty frame t; same id at t+0.17 → continues, extra steps are counted; no freezeCursor(false) yet */ }
@Test func lostFingerExpiresCommits() { /* empty frame t; empty frame t+0.181 → .idle and freezeCursor(false) once */ }
@Test func watchdogTickCommits() { /* slide; tick(now: last + 0.181) → .idle, freezeCursor(false) */ }
@Test func backwardsTimestampDoesNotCommit() { /* slide; tick(now: last - 1) → still .sliding, no commands */ }
@Test func reusedIDAfterLostExpiryStartsFresh() { /* after lost expires, the same id at 115,15 → .candidate, no steps */ }
@Test func switchAppsStepsAndCommit() { /* top edge: 30,78 → 54,78 → 2 × appSwitchStep(1); lift and 181 ms → appSwitchCommit */ }
@Test func switchAppsSecondFingerCancels() { /* appSwitchCancel */ }
@Test func scrubStepsAndCommit() { /* cfg.top = .scrubVideo; 12 mm → 2 × scrubStep(1); commit */ }
@Test func updateConfigDuringSlideCommits() { /* sliding; update(config:) → .idle, freezeCursor(false); appSwitchCommit if switchApps */ }
@Test func frameFromOtherDeviceIgnoredWhileSliding() { /* frames with deviceID 2 do not change the state */ }
@Test func freezeCursorEmittedOncePerSlide() { /* freezeCursor(true) 1, (false) 1 */ }
@Test func freezeCursorDisabledInConfigEmitsNothing() { /* cfg.freezeCursor = false → no freezeCursor command */ }
@Test func cornerCandidateBindsToVerticalEdgeOnVerticalMove() { /* 115,5 → 115,40 → stepVolume steps */ }
```

- [ ] **Step 2: Run** — Expected: build error (`GestureEngine` missing).

- [ ] **Step 3: Write the state machine** — the spec 5.4 transitions (1–4 and `spent` → `idle` when all fingers lift); on entering `sliding`, `accumulatedMM` includes the starting distance; the step loop is `while abs(acc) >= step`; `finish(commit/cancel)` are the commands in the spec; `lost` expires with both a frame and `tick`; `tick(now:)` does nothing if `now < lastFrameTime`; `update(config:)` commits while sliding and then changes the config; `reset()` returns to idle. No heap allocation (the enum states are value types).

- [ ] **Step 4: Run** — Run: `swift test 2>&1 | tail -3` — Expected: all pass.

- [ ] **Step 5: Commit and PR** — `make check && git commit -am "feat(engine): add slide state machine with lost-finger recovery and watchdog"`; branch `feat/engine-slide`; CHANGELOG line.

---

### Task 6: Taps: corner double tap, media double tap, three-finger middle click

**Files:**
- Modify: `Sources/TrrekEngine/GestureEngine.swift`, `Sources/TrrekEngine/EngineState.swift`
- Create: `Tests/TrrekEngineTests/TapTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 5 `GestureEngine`.
- Produces: the spec 5.4 `candidate` tap branch, the `spent`/`idle` → `threeFinger` transitions; `lastTap: (corner: Corner?, edge: Edge?, at: TimeInterval)?` in `EngineState`.

- [ ] **Step 1: Failing tests** — `TapTests.swift`:

```swift
@Test func plainEdgeTapEmitsNothing() { /* 115,40 lands, lifts 0.1 s later → no commands, .idle */ }
@Test func cornerDoubleTapWithinWindowMutes() { /* cfg.bottomRight = .mute; two taps 0.3 s apart → mute 1, haptic(.tap) 1 */ }
@Test func cornerDoubleTapOutsideWindowDoesNothing() { /* 0.36 s apart → mute 0 */ }
@Test func cornerDoubleTapOffDoesNothing() { /* default off → no commands */ }
@Test func screenshotCornerEmitsScreenshot() { /* cfg.topLeft = .screenshot */ }
@Test func mediaEdgeDoubleTapPlaysPauses() { /* cfg.bottom = .media; 60,5 two taps → mediaPlayPause 1 */ }
@Test func mediaEdgeSlideSkipsTrack() { /* 20 mm to the right → mediaNext 1; to the left → mediaPrevious */ }
@Test func threeFingerTapEmitsMiddleClick() { /* middleClickEnabled; three fingers in the same frame 0.05 s; on lift middleClick 1, haptic(.tap) 1 */ }
@Test func threeFingerStaggeredLandingStillCounts() { /* id1 t=0, id2 t=0.03, id3 t=0.06 (all outside zones); on lift middleClick */ }
@Test func threeFingerDisabledDoesNothing() { }
@Test func threeFingerMovementCancels() { /* one finger moves 3 mm → middleClick 0 */ }
@Test func threeFingerTooLongCancels() { /* held 0.35 s → 0 */ }
@Test func fourthFingerCancels() { }
```

- [ ] **Step 2: Run** — Expected: the relevant tests fail.

- [ ] **Step 3: Write the transitions** — the spec 5.4 `candidate` lift branch (duration `max(0, t − t0)`), double tap with `lastTap`, `idle`/`candidate`/`spent` → `threeFinger` (the first landing time is in the `spent` data), the `threeFinger` exits.

- [ ] **Step 4: Run** — Expected: all pass; the Task 5 tests still pass.

- [ ] **Step 5: Commit and PR** — `feat(engine): add corner and media double-taps and three-finger middle click`; branch `feat/engine-taps`.

---

### Task 7: Gates and configuration updates

**Files:**
- Modify: `Sources/TrrekEngine/GestureEngine.swift`
- Create: `Tests/TrrekEngineTests/GateTests.swift`
- Modify: `CHANGELOG.md`, `README.md` (Engine section: summary of the rules)

**Interfaces:**
- Consumes: Task 6 `GestureEngine`.
- Produces: the full behavior of `noteKeyDown(at:)`, `setHoldKeySatisfied(_:)`, `setPaused(_:)` (spec 5.6); the palm filter at the entry of `process`.

- [ ] **Step 1: Failing tests** — `GateTests.swift`:

```swift
@Test func palmTouchIsFiltered() { /* major 21 → no zone, no step; major 19 → slide works */ }
@Test func palmAlongsideFingerDoesNotCancelSlide() { /* id1 finger slide + id2 major 30 → slide continues */ }
@Test func typingGateBlocksNewGesture() { /* noteKeyDown(at: 0); frames at 0.1 → no step; a slide starting at 0.5 works */ }
@Test func typingDoesNotStopActiveSlide() { /* noteKeyDown in the middle of a slide → steps continue */ }
@Test func holdKeyRequiredBlocksWithoutKey() { /* holdKeyRequired, satisfied false → no step; true → works */ }
@Test func releasingHoldKeyCommitsSlide() { /* sliding; setHoldKeySatisfied(false) → .idle, freezeCursor(false) */ }
@Test func pausedIgnoresFrames() { /* setPaused(true) → no step */ }
@Test func pausingEndsActiveSlide() { /* sliding; setPaused(true) → .idle, freezeCursor(false), commit if switchApps */ }
@Test func swappedSidesChangeCommandType() { /* cfg.right = .brightness → stepBrightness */ }
@Test func resetEmitsFreezeOffOnlyWhenFrozen() { /* reset while idle → no commands; reset while sliding → freezeCursor(false) 1 */ }
```

- [ ] **Step 2: Run** — Expected: the relevant tests fail.

- [ ] **Step 3: Write the gates** — the spec 5.6 order; the palm filter by copying from `TouchBuffer` into a new buffer (stack, no heap).

- [ ] **Step 4: Run** — Run: `swift test 2>&1 | tail -3` — Expected: a total of ≥ 55 tests pass.

- [ ] **Step 5: README Engine section** — a one-paragraph summary of the rules and the `swift test` command.

- [ ] **Step 6: Commit and PR** — `feat(engine): add palm, typing, hold-key and pause gates`; branch `feat/engine-gates`. After merge, `make check` is green on main; the Engine lines in the CHANGELOG are complete.

---

## Self-review notes

- Spec coverage: Section 4 (package) → Task 1; 7.8 and 10.x → Task 2; 6.1, 6.2 (raw part), 6.3, 6.4, 6.5 (Tap B), 6.6 (KeyPoster), 6.10 (Permissions) → Task 3; 11 Phase 0 → Task 3b; 5.1–5.3, 5.7 → Task 4; 5.4 (1–4), 5.5, 5.8 → Task 5; 5.4 (tap, 5, 6) → Task 6; 5.6 → Task 7. All 26 tests in spec 9.1 are in the Task 4–7 test lists; the 5 tests of Review Focus are in Tasks 4, 5 and 7.
- Next plan: the remaining Platform bridges (6.5 Tap A, 6.7, the rest of 6.10), `Coordinator`, menu, settings window, welcome, overlay, `docs/testing.md`, perf measurement and `v0.1.0`.
