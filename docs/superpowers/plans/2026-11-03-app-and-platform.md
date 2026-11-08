# trrek Platform Bridges, Menu Bar App and Liquid Glass UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A platform pipeline that connects the gesture engine to the real trackpad, system events and haptics; a working `trrek.app` with settings, a menu bar menu, Liquid Glass settings and welcome windows, and an overlay; a manual test list, performance measurement and the `v0.1.0` release (spec Phase 1).

**Architecture:** A testable pipeline is added to `TrrekPlatform`: `FrameConverter` (raw touch → `Frame`), `GesturePipeline` (stream + lock + watchdog + activity), `CommandDispatcher` (command → system actions behind protocols). The app logic (`Settings`, `SettingsStore`, `ConfigMapper`) is tested in the new `TrrekAppCore` library; the `Trrek` executable target carries the AppKit lifecycle, the menu and the SwiftUI windows.

**Tech Stack:** Swift 6 (tools 6.0), Swift Testing, AppKit, SwiftUI (macOS 26 Liquid Glass: `glassEffect`, `TabView`, `Form`), CoreGraphics event taps, private CoreBrightness (dlsym/NSClassFromString), ServiceManagement, IOKit notifications.

**Spec:** `docs/superpowers/specs/2026-11-03-trrek-design.md` (sections 3, 6, 7, 8, 9, 10, 11) and `docs/superpowers/specs/2026-11-03-spike-results.md`

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 language mode, `.macOS("26.0")`, arm64 only; no Swift 6.3+ language features and no macOS 27 APIs (CI: Xcode 26.6 / Swift 6.2).
- Private symbols only in `Sources/TrrekPlatform/PrivateSymbols.swift` (dlopen/dlsym; the class and selector names for CoreBrightness are also here); a missing symbol turns the feature off, it does not crash.
- No other app/library/project name appears in the project; code and UI are in English; documents in Turkish. The app name is `trrek`, bundle `com.burakseyitkara.trrek`.
- Performance: 0% CPU at idle, memory under 15 MB; no heap allocation on the frame path; no periodic timers (only the slide watchdog and overlay hiding, both one-shot); SwiftUI windows are released when closed.
- The frame callback runs on a framework thread; Engine calls are under `os_unfair_lock`; AppKit/SwiftUI work is on `MainActor`.
- Each task on its own branch with a PR; `make check` green locally; squash merge.
- The menu and settings window layout is as in spec 7.2 and 7.3; the settings fields and their defaults are as in spec 7.4.

## Review Focus

1. When the trackpad list is empty or the devices are re-enumerated after sleep, the pipeline must drop into the "Trackpad not found" state without crashing, and start by itself when the device arrives (Task 2 `DeviceHotplugObserver` + Task 3 status line; manual test `docs/testing.md`).
2. Corrupt or old-schema settings data (different `schemaVersion`, unknown enum value) must fall back to defaults and not crash (Task 3 test `storeFallsBackToDefaultsOnCorruptData`).
3. If the app quits before `appSwitchCommit` arrives, ⌘ must not stay held (Task 1 `CommandDispatcher.releaseAll()` + Task 3 call on exit; test `releaseAllReleasesHeldModifier`).
4. When the keyboard backlight bridge is missing, the bottom edge default must fall back to Media and the option must be disabled in settings (Task 3 test `bottomEdgeFallsBackToMediaWithoutBacklight`, Task 4 UI).
5. In the Hold-to-Slide "Toggle" mode, pressing the modifier together with another key must not change the state (Task 2 test `toggleIgnoresModifierUsedAsChord`).

---

### Task 1: Frame converter, gesture pipeline and command dispatcher

**Files:**
- Create: `Sources/TrrekPlatform/Pipeline/Ports.swift`, `Sources/TrrekPlatform/Pipeline/FrameConverter.swift`, `Sources/TrrekPlatform/Pipeline/GesturePipeline.swift`, `Sources/TrrekPlatform/Pipeline/CommandDispatcher.swift`, `Sources/TrrekPlatform/Input/MousePoster.swift`, `Sources/TrrekPlatform/Input/SystemPosters.swift`
- Modify: `Sources/TrrekPlatform/Multitouch/RawFrameStream.swift` (`onFrame` `@Sendable`; `stop()` documentation), `Sources/TrrekPlatform/Multitouch/MultitouchDevices.swift` (drop the old list on re-enumeration), `Sources/TrrekPlatform/Haptics/ActuatorHaptics.swift` (`HapticPerforming`), `Sources/TrrekPlatform/Input/EventTapGuard.swift` (`.cghidEventTap`, `CursorFreezing`, `@MainActor` creation), `Package.swift` (`TrrekPlatformTests` target; explicit `CMultitouch` dependency for `TrrekProbe`), `CHANGELOG.md`
- Create: `Tests/TrrekPlatformTests/FrameConverterTests.swift`, `Tests/TrrekPlatformTests/CommandDispatcherTests.swift`, `Tests/TrrekPlatformTests/Support/Fakes.swift`

**Interfaces:**
- Consumes: `MTTouch` (CMultitouch), `MultitouchDeviceInfo`, `RawFrameStream`, `ActuatorHaptics.actuate(waveform:)`, `MediaKeyPoster.post(_:fine:)`, `KeyPoster.press/modifierDown/modifierUp`, `EventTapGuard.setFreeze`, `GestureEngine`, `GestureCommand`, `HapticEvent`, `DeviceGeometry`, `Frame`.
- Produces:
  - `public enum HapticStrength: String, CaseIterable, Codable, Sendable { case off, light, medium, strong }`
  - `public enum OverlayKind: Sendable { case keyboardBacklight, externalBrightness, scrub }`
  - Protocols (all `Sendable`): `MediaKeyPosting { func post(_ key: MediaKey, fine: Bool) }`, `KeyPosting { func press(keyCode: CGKeyCode, flags: CGEventFlags); func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags); func modifierUp(_ keyCode: CGKeyCode) }`, `MousePosting { func middleClick() }`, `HapticPerforming { func perform(_ event: HapticEvent, strength: HapticStrength) }`, `CursorFreezing { func setFreeze(_ on: Bool) }`, `KeyboardBacklightControlling { var isAvailable: Bool { get }; func step(_ direction: Int, fine: Bool) -> Float? }` (new level 0…1), `LevelOverlayPresenting { func show(kind: OverlayKind, level: Float, label: String?) }`
  - `public enum FrameConverter { public static func frame(touches: UnsafeBufferPointer<MTTouch>, timestamp: Double, deviceID: UInt64, geometry: DeviceGeometry) -> Frame }` — only `state ∈ {3, 4}`; `x = nx`, `y = ny`, `majorAxisMM = majorAxis`; more than 16 are dropped.
  - `public final class GesturePipeline: @unchecked Sendable { public init(engine: GestureEngine, lostTimeout: TimeInterval); public private(set) var isRunning: Bool; public var deviceCount: Int; public func start() throws; public func stop(); public func restart() }` — gets the devices with `MultitouchDevices.enumerate()`, builds an `MTDeviceRef` → (`UInt64` id, `DeviceGeometry`) table, runs `FrameConverter` + `engine.process` under `os_unfair_lock` inside `RawFrameStream.onFrame`; on every frame, if `engine.stateKind ∈ {sliding, lost}`, it re-arms a one-shot `DispatchSourceTimer` with `lostTimeout` (when it fires, `engine.tick(now:)` under the lock); on entering `sliding`, `ProcessInfo.processInfo.beginActivity(.userInitiated, reason: "trrek slide")`, on leaving, `endActivity`. `start()` throws `PipelineError.noDevices` if there are no devices.
  - `public final class CommandDispatcher: CommandSink, @unchecked Sendable { public init(mediaKeys: any MediaKeyPosting, keys: any KeyPosting, mouse: any MousePosting, haptics: any HapticPerforming, freezer: any CursorFreezing, backlight: (any KeyboardBacklightControlling)?, overlay: (any LevelOverlayPresenting)?); public var hapticStrength: HapticStrength; public func handle(_ command: GestureCommand, device: UInt64); public func releaseAll() }` — mapping: `stepVolume(+1/−1, fine)` → `soundUp/soundDown`; `stepBrightness` → `brightnessUp/Down`; `stepKeyboardBacklight` → `backlight?.step(dir, fine:)` and with the returned level `overlay?.show(kind: .keyboardBacklight, level:, label: nil)` (nothing if there is no bridge); `appSwitchStep(n)`: on the first step `modifierDown(55, .maskCommand)` and `switcherHeld = true`, on every step `press(48, n > 0 ? .maskCommand : [.maskCommand, .maskShift])`; `appSwitchCommit` → `modifierUp(55)`; `appSwitchCancel` → `press(53, .maskCommand)` then `modifierUp(55)`; `scrubStep/Commit/Cancel` → ignored in Phase 1 (log `info`); `mediaPlayPause/Next/Previous` → `play/next/previous`; `mute` → `mute`; `screenshot` → `press(23, [.maskCommand, .maskShift])`; `middleClick` → `mouse.middleClick()`; `haptic(e)` → `haptics.perform(e, strength:)`; `freezeCursor(b)` → `freezer.setFreeze(b)`. `releaseAll()`: if `switcherHeld`, `modifierUp(55)`, `freezer.setFreeze(false)`.
  - `public struct SystemMediaKeys: MediaKeyPosting`, `SystemKeys: KeyPosting`, `SystemMouse: MousePosting` (wrap the existing `MediaKeyPoster`/`KeyPoster`/`MousePoster` enums).
  - `public enum MousePoster { static func middleClick() }` — `CGEvent(mouseEventSource: EventStamp.source, mouseType: .otherMouseDown/.otherMouseUp, mouseCursorPosition: <cursor, CG coordinates>, mouseButton: .center)`, `mouseButtonNumber = 2`, stamped, `.cghidEventTap`.
  - `ActuatorHaptics: HapticPerforming`: `off` → nothing; `light/medium/strong` → waveform 4/5/6; for `strong` and event `.start`/`.tap`, a second pulse 60 ms later (`DispatchQueue.global().asyncAfter`, one-shot). `.limit` like a step.
  - `EventTapGuard: CursorFreezing`; tap location `.cghidEventTap`; `init` is `@MainActor`.
  - Test fakes: `FakeMediaKeys`, `FakeKeys`, `FakeMouse`, `FakeHaptics`, `FakeFreezer`, `FakeBacklight(level:)`, `FakeOverlay` — record calls into an array.

- [ ] **Step 1: Failing tests** — `FrameConverterTests.swift`:

```swift
@Test func converterKeepsOnlyTouchingStates() { /* state 1,3,4,5 → only 3 and 4 (count 2) */ }
@Test func converterMapsFields() { /* nx 0.5, ny 0.25, majorAxis 8.5 → Touch x 0.5, y 0.25, majorAxisMM 8.5; id = identifier */ }
@Test func converterTruncatesAtSixteen() { /* 20 touching → count 16 */ }
```
`CommandDispatcherTests.swift`:
```swift
@Test func volumeStepsPostMediaKeys() { /* +1 → soundUp fine false; −1 fine true → soundDown fine true */ }
@Test func switcherProtocol() { /* appSwitchStep(1) → modifierDown(55, cmd) then press(48, cmd); appSwitchStep(-1) → press(48, cmd+shift) only; appSwitchCommit → modifierUp(55) */ }
@Test func switcherCancelSendsEscapeThenReleases() { }
@Test func releaseAllReleasesHeldModifier() { /* step then releaseAll → modifierUp(55) exactly once; freezer false */ }
@Test func backlightStepShowsOverlay() { /* FakeBacklight level 0.5 → step(+1,false) → overlay show(.keyboardBacklight, 0.5625) */ }
@Test func backlightMissingDoesNothing() { }
@Test func hapticsOffPerformsNothing() { /* strength off → FakeHaptics empty; medium → perform(.step, .medium) */ }
@Test func cornerAndMediaCommands() { /* mute → mute; screenshot → press(23, cmd+shift); mediaNext → next; middleClick → mouse 1 */ }
@Test func freezeCommandsForward() { }
```

- [ ] **Step 2: Run** — Run: `make test 2>&1 | tail -3` — Expected: build error (target/types missing).

- [ ] **Step 3: Package.swift** — `TrrekPlatformTests` (testTarget, dependencies: TrrekPlatform, TrrekEngine); add `CMultitouch` to the `TrrekProbe` dependencies.

- [ ] **Step 4: Ports, FrameConverter, Dispatcher, posters, hygiene changes** — the signatures in the Interfaces block; the `RawFrameStream.onFrame` type is `(@Sendable (MTDeviceRef, UnsafeBufferPointer<MTTouch>, Double) -> Void)?`; `MultitouchDevices.enumerate()` drops the previous list only when no stream is running (simple: keep the last list instead of `retainedLists`, the old one is released after `stop()`).

- [ ] **Step 5: GesturePipeline** — the behavior in the Interfaces block; no allocation in the frame callback (a small fixed array instead of a dictionary for table lookup; device count ≤ 4).

- [ ] **Step 6: Run** — Run: `make test 2>&1 | tail -3` — Expected: all tests pass (Engine 68 + Platform ≥ 12).

- [ ] **Step 7: Live verification with the probe** — add a `pipeline [seconds]` command to `TrrekProbe`: `GestureEngine(config: EngineConfig(), sink: LoggingSink)` + `GesturePipeline`; it prints each command on one line (sends no system action). Run: `swift build && .build/debug/TrrekProbe pipeline 20` and slide up on the right edge — Expected: `stepVolume(1)` lines and `haptic(.step)`; on lift-off `freezeCursor(false)`.

- [ ] **Step 8: Commit and PR** — `make check && git add -A && git commit -m "feat(platform): add frame converter, gesture pipeline and command dispatcher"`; branch `feat/platform-pipeline`; CHANGELOG line `- Platform: gesture pipeline, command dispatcher and testable ports`.

---

### Task 2: Input monitoring, Hold-to-Slide, keyboard backlight and system observers

**Files:**
- Create: `Sources/TrrekPlatform/Input/InputMonitor.swift`, `Sources/TrrekPlatform/Input/HoldKeyTracker.swift`, `Sources/TrrekPlatform/Keyboard/KeyboardBacklight.swift`, `Sources/TrrekPlatform/System/FrontmostObserver.swift`, `Sources/TrrekPlatform/System/WakeObserver.swift`, `Sources/TrrekPlatform/System/DeviceHotplugObserver.swift`, `Sources/TrrekPlatform/System/LaunchAtLogin.swift`
- Modify: `Sources/TrrekPlatform/PrivateSymbols.swift` (CoreBrightness: framework path, `KeyboardBrightnessClient` class name, selector names), `Sources/TrrekPlatform/System/Permissions.swift` (`onChange`), `Sources/TrrekProbe/Commands.swift` (`backlight` and `keys` commands), `CHANGELOG.md`
- Create: `Tests/TrrekPlatformTests/HoldKeyTrackerTests.swift`

**Interfaces:**
- Consumes: `EventStamp.isOurs`, `KeyboardBacklightControlling`, `MultitouchDevices`.
- Produces:
  - `public enum HoldKey: String, CaseIterable, Codable, Sendable { case none, shift, control, option, command; var flag: CGEventFlags? }`, `public enum HoldKeyMode: String, CaseIterable, Codable, Sendable { case hold, toggle }`
  - `public struct HoldKeyTracker: Sendable { public init(key: HoldKey, mode: HoldKeyMode); public private(set) var isSatisfied: Bool; public mutating func handleFlagsChanged(_ flags: CGEventFlags, at: TimeInterval) -> Bool; public mutating func handleKeyDown(at: TimeInterval); public mutating func reset() }` — `none` → always `true`; `hold` → `true` while the modifier is held; `toggle` → if the modifier is pressed alone and released within `≤ 0.3 s` and no `handleKeyDown` arrived in between, `isSatisfied.toggle()`; the return value is "did it change".
  - `public final class InputMonitor { @MainActor public init(); public var isAvailable: Bool; public var onKeyDown: (@Sendable (TimeInterval) -> Void)?; public var onFlagsChanged: (@Sendable (CGEventFlags, TimeInterval) -> Void)?; @MainActor public func start(); @MainActor public func stop() }` — Tap A: `.cgSessionEventTap`, `.listenOnly`, `[keyDown, flagsChanged]`; stamped events are ignored; `tapDisabledByTimeout` → re-enable; callbacks on the main run loop.
  - `public final class KeyboardBacklight: KeyboardBacklightControlling { public init?(); public var isAvailable: Bool; public func level() -> Float?; public func step(_ direction: Int, fine: Bool) -> Float? }` — via `PrivateSymbols.coreBrightness`, `NSClassFromString("KeyboardBrightnessClient")`, `copyKeyboardBacklightIDs`, `brightnessForKeyboard:`, `setBrightness:fadeSpeed:commit:forKeyboard:` (`@convention(c)` IMPs through `unsafeBitCast`); step `1/16` (fine `1/64`), clamped to 0…1; `nil` if there is no keyboard ID.
  - `public final class FrontmostObserver { public init(); public var onChange: (@Sendable (String?) -> Void)?; public static var currentBundleID: String?; public func start(); public func stop() }` (`NSWorkspace.shared.notificationCenter`, `didActivateApplicationNotification`).
  - `public final class WakeObserver { public init(); public var onWake: (@Sendable () -> Void)?; start/stop }` (`NSWorkspace.didWakeNotification`).
  - `public final class DeviceHotplugObserver { public init(); public var onChange: (@Sendable () -> Void)?; start/stop }` — `AppleMultitouchDevice` `kIOMatchedNotification` and `kIOTerminatedNotification` with `IOServiceAddMatchingNotification`; the iterators are drained; the run loop source is on the main run loop.
  - `public enum LaunchAtLogin { public static var isEnabled: Bool; public static func setEnabled(_ on: Bool) throws }` (`SMAppService.mainApp`).
  - `Permissions.onChange: (@Sendable (Bool) -> Void)?` + `startObserving()` (`DistributedNotificationCenter.default()` `"com.apple.accessibility.api"`).

- [ ] **Step 1: Failing tests** — `HoldKeyTrackerTests.swift`:

```swift
@Test func noneIsAlwaysSatisfied() { }
@Test func holdFollowsModifierState() { /* flags with .maskShift → true; without → false */ }
@Test func toggleFlipsOnLonePressRelease() { /* down at 0, up at 0.2 → true; again → false */ }
@Test func toggleIgnoresSlowRelease() { /* down 0, up 0.5 → unchanged */ }
@Test func toggleIgnoresModifierUsedAsChord() { /* down 0, keyDown 0.1, up 0.2 → unchanged */ }
@Test func resetClearsToggle() { }
```

- [ ] **Step 2: Run** — Expected: build error.
- [ ] **Step 3: Write HoldKeyTracker and the other bridges** — Interfaces block.
- [ ] **Step 4: Run** — Run: `make test 2>&1 | tail -3` — Expected: all pass.
- [ ] **Step 5: Probe commands** — `backlight get|up|down` (level via CoreBrightness), `keys [seconds]` (InputMonitor: one line for each keyDown/flagsChanged; stamped events are not visible). Run: `.build/debug/TrrekProbe backlight get` — Expected: a number between 0…1 or `unavailable`.
- [ ] **Step 6: Commit and PR** — `feat(platform): add input monitor, hold-key tracker, keyboard backlight and system observers`; branch `feat/platform-system`; CHANGELOG line.

---

### Task 3: App core — settings, coordinator, menu bar

**Files:**
- Create: `Sources/TrrekAppCore/Settings.swift`, `Sources/TrrekAppCore/SettingsStore.swift`, `Sources/TrrekAppCore/ConfigMapper.swift`
- Create: `Sources/Trrek/main.swift` (rewrite), `Sources/Trrek/AppDelegate.swift`, `Sources/Trrek/Coordinator.swift`, `Sources/Trrek/Menu/StatusMenu.swift`, `Sources/Trrek/Menu/MenuIcon.swift`, `Sources/Trrek/UI/WindowRegistry.swift`
- Modify: `Package.swift` (`TrrekAppCore` library: depends on TrrekEngine, TrrekPlatform; add to the `Trrek` dependencies; `TrrekAppCoreTests`), `Resources/Info.plist.in` (unchanged), `CHANGELOG.md`
- Create: `Tests/TrrekAppCoreTests/SettingsStoreTests.swift`, `Tests/TrrekAppCoreTests/ConfigMapperTests.swift`

**Interfaces:**
- Consumes: Task 1–2 types, `EngineConfig`, `Thresholds`.
- Produces:
  - `public enum EdgeWidth: String, CaseIterable, Codable, Sendable { case narrow, standard, wide; public var millimetres: Float }` (7, 10, 14)
  - `public struct Settings: Codable, Equatable, Sendable` — the spec 7.4 fields and defaults; instead of `corners: [Corner: CornerAction]`, four fields `topLeft, topRight, bottomLeft, bottomRight: CornerAction`; `public static let current schemaVersion = 1`; `public init()`.
  - `public final class SettingsStore: @unchecked Sendable { public init(defaults: UserDefaults = .standard, key: String = "settings"); public func load() -> Settings; public func save(_ settings: Settings) }` — JSON; decode error or `schemaVersion != 1` → `Settings()` + log `error`.
  - `public enum ConfigMapper { public static func engineConfig(from settings: Settings, backlightAvailable: Bool) -> EngineConfig; public static func effectiveBottomEdge(_ settings: Settings, backlightAvailable: Bool) -> EdgeAction }` — swap sides: `left = volume, right = brightness`; `edgeWidthMM = settings.edgeWidth.millimetres`; `bottom = keyboardBacklight` but `.media` if there is no bridge; `holdKeyRequired = settings.holdKey != .none`; `externalMonitorBrightness` and `scrubVideo` have no effect on EngineConfig in Phase 1 (if scrubVideo is selected, `.off`).
  - `Coordinator` (`@MainActor final class`): `init(store: SettingsStore)`; `start()` (permission check → bridges → engine → pipeline → input monitor → frontmost/wake/hotplug observers → menu); `apply(_ settings: Settings)` (write to the store, `engine.update(config:)`, `dispatcher.hapticStrength`, rebuild `holdKeyTracker`, `LaunchAtLogin`); `statusText: String` ("trrek is active" / "Paused in <App>" / "Accessibility access needed" / "Trackpad not found" / "Trackpad data unavailable"); `pauseInFrontApp()`, `resumeInFrontApp()`; `openSettings()`, `showWelcome()`, `grantAccessibility()`; `terminate()` (`dispatcher.releaseAll()`, close taps, stop pipeline).
  - `StatusMenu` (`@MainActor`): `NSStatusItem` + `NSMenu` in the spec 7.2 layout; refresh through `NSMenuDelegate.menuNeedsUpdate`; icon `MenuIcon.image(active:)` — an 18×18 pt template image drawn in code (rounded rectangle frame + a filled vertical strip on the right edge; a 4 pt dot at the bottom right when Toggle is active).
  - `WindowRegistry` (`@MainActor`): optional references `settingsWindow`, `welcomeWindow`; Tasks 4–5 fill them; in this task `openSettings()`/`showWelcome()` only write a log.
  - Launch arguments (`AppDelegate`): `--settings`, `--welcome` (open the respective window; become active in Tasks 4–5), `--quit-after <seconds>` (for perf/screenshots).

- [ ] **Step 1: Failing tests** — `SettingsStoreTests.swift`: `roundTripPreservesAllFields` (with every field set to a value different from the default), `storeFallsBackToDefaultsOnCorruptData` (`defaults.set(Data("x".utf8), forKey:)` → `Settings()`), `storeFallsBackOnSchemaMismatch`. `ConfigMapperTests.swift`: `defaultMappingMatchesSpec`, `swapSidesSwapsLeftRight`, `edgeWidthMapsToMillimetres` (7/10/14), `bottomEdgeFallsBackToMediaWithoutBacklight`, `holdKeyNoneDoesNotRequireKey`, `scrubVideoIsOffInPhaseOne`. `UserDefaults(suiteName: "trrek.tests")` + `removePersistentDomain`.
- [ ] **Step 2: Run** — Expected: build error.
- [ ] **Step 3: TrrekAppCore** — Interfaces block.
- [ ] **Step 4: Run** — Expected: pass.
- [ ] **Step 5: App** — `main.swift`: `NSApplication.shared`, `setActivationPolicy(.accessory)`, assign `AppDelegate`, `NSApp.run()`. `AppDelegate.applicationDidFinishLaunching` → `Coordinator.start()`; `applicationWillTerminate` → `terminate()`. Menu, coordinator, icon.
- [ ] **Step 6: Package and live verification** — Run: `make install && open ~/Applications/trrek.app && sleep 3 && pgrep -x trrek && screencapture -x /tmp/trrek-menubar.png` — Expected: the process is running; the icon is visible in the menu bar (screenshot top right). On first launch the macOS Accessibility prompt appears (the user grants it). Run: `scripts/perf.sh` — Expected: RSS < 15360 KB, CPU 0.0.
- [ ] **Step 7: Commit and PR** — `feat(app): add settings model, coordinator and menu bar menu`; branch `feat/app-core`; CHANGELOG line `- App: settings store, coordinator, menu bar menu, launch at login`.

---

### Task 4: Settings window (SwiftUI, Liquid Glass)

**Files:**
- Create: `Sources/Trrek/UI/SettingsWindowController.swift`, `Sources/Trrek/UI/SettingsModel.swift`, `Sources/Trrek/UI/SettingsView.swift`, `Sources/Trrek/UI/GeneralTab.swift`, `Sources/Trrek/UI/EdgesTab.swift`, `Sources/Trrek/UI/CornersTab.swift`, `Sources/Trrek/UI/AdvancedTab.swift`, `Sources/Trrek/UI/TrackpadDiagram.swift`, `Sources/Trrek/UI/PausedAppsList.swift`
- Modify: `Sources/Trrek/Coordinator.swift` (`openSettings()`), `Sources/Trrek/UI/WindowRegistry.swift`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `Settings`, `Coordinator.apply(_:)`, `Permissions`, `KeyboardBacklight.isAvailable`.
- Produces:
  - `@MainActor @Observable final class SettingsModel { init(settings: Settings, backlightAvailable: Bool, onChange: @escaping (Settings) -> Void); var settings: Settings { didSet { onChange(settings) } }; let backlightAvailable: Bool; var accessibilityGranted: Bool }`
  - `SettingsView(model:)` — a `TabView` with four tabs: "General", "Edges", "Corners & Taps", "Advanced"; each tab is a `Form` + `.formStyle(.grouped)`; window fixed at 640×480; `.glassEffect(.regular, in: .rect(cornerRadius: 12))` only on the `TrackpadDiagram` surface and the corner badges.
  - `TrackpadDiagram(settings: Settings, backlightAvailable: Bool, interactive: Bool)` — a rounded trackpad silhouette with a 3:2 ratio; four edge strips with color and label (right blue "Volume", left yellow "Brightness", top/bottom labeled by the selected action, gray "Off" if `off`); four corner badges (Off/Mute/Screenshot icon); if `interactive`, clicking a corner badge cycles through the options.
  - Tab contents per spec 7.3: General (Haptic Feedback segment, Precision Control, Freeze Cursor, Launch at Login, Reset to Defaults… with confirmation); Edges (diagram, Swap Sides, Top Edge/Bottom Edge `Picker` — `Keyboard Backlight` is disabled with "Not available on this Mac" if there is no bridge, `Scrub Video` is disabled "Coming later"; Edge Width segment; Bottom Quarter Only; External Monitor Brightness disabled "Coming later"); Corners & Taps (diagram + four `Picker`s, 3-Finger Tap Middle Click, hint text "Set Look up & data detectors to Force click with one finger in System Settings › Trackpad"); Advanced (Hold-to-Slide Key `Picker` + mode segment, `PausedAppsList` (+ `NSOpenPanel` `/Applications`, − removes; the row has `NSWorkspace.shared.icon(forFile:)` and the name), Accessibility status + "Open System Settings", version).
  - `SettingsWindowController` (`@MainActor`): `show(model:)` → `NSWindow` (`[.titled, .closable, .miniaturizable]`, `titlebarAppearsTransparent`, `toolbarStyle = .unified`) + `NSHostingController`; `isReleasedWhenClosed = false` but on close `WindowRegistry.settingsWindow = nil` (the hosting controller is released).

- [ ] **Step 1: Write the views** — Interfaces block; texts in English; SF Symbols: `speaker.wave.2`, `sun.max`, `keyboard`, `rectangle.on.rectangle`, `play`, `speaker.slash`, `camera.viewfinder`.
- [ ] **Step 2: Coordinator wiring** — `openSettings()`: if there is no model, create `SettingsModel(settings: current, ...)`, `onChange` → `apply`; bring the window to the front (`NSApp.activate`).
- [ ] **Step 3: Live verification** — Run: `make install && open ~/Applications/trrek.app --args --settings && sleep 2 && screencapture -x /tmp/trrek-settings.png` — Expected: the window is visible; four tabs; the diagram has a glass surface. A screenshot for each tab (the `--settings general|edges|corners|advanced` argument selects the tab). Change a setting, quit and reopen the app → persisted.
- [ ] **Step 4: make check and commit** — `feat(app): add Liquid Glass settings window`; branch `feat/app-settings-window`; CHANGELOG line.

---

### Task 5: Overlay and welcome window

**Files:**
- Create: `Sources/Trrek/UI/OverlayPanel.swift`, `Sources/Trrek/UI/OverlayView.swift`, `Sources/Trrek/UI/WelcomeWindowController.swift`, `Sources/Trrek/UI/WelcomeView.swift`
- Modify: `Sources/Trrek/Coordinator.swift` (give the overlay to the dispatcher; first run; `showWelcome`), `Sources/Trrek/AppDelegate.swift` (`--welcome`, `--demo-overlay`), `CHANGELOG.md`

**Interfaces:**
- Consumes: `LevelOverlayPresenting`, `OverlayKind`, `Permissions`, `TrackpadDiagram`, `Settings.welcomeShown`.
- Produces:
  - `@MainActor final class OverlayPanel: LevelOverlayPresenting` — `nonisolated func show(kind:level:label:)` hops to the main actor; the panel is created on the first call (`NSPanel` `[.borderless, .nonactivatingPanel]`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = true`, `hasShadow = false`), `NSHostingView<OverlayView>`; position: the `NSScreen` where the cursor is, top right, 16 pt gap, 220×56 pt; hidden 1.0 s after the last `show` (`DispatchWorkItem`, the previous one is cancelled); the content is not updated while hidden.
  - `OverlayView(kind: OverlayKind, level: Float, label: String?)` — `.glassEffect(.regular, in: .capsule)`; SF Symbol (`keyboard`, `sun.max`, `film`), a 16-segment level bar (`level * 16` rounded), on the right `label ?? "\(Int(level*100))%"`.
  - `WelcomeView(model:)` 560×440: title "Welcome to trrek", `TrackpadDiagram(interactive: false)`, four glass cards (`glassEffect`): "Right edge — Volume", "Left edge — Brightness", "Top edge — Switch apps", "Bottom edge — Keyboard backlight" ("Media" if there is no bridge); an Accessibility status row and a "Grant Accessibility Access" button (`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`), "Open Settings", "Done".
  - `WelcomeWindowController.show(...)`; released on close.
  - `Coordinator`: on first run (`welcomeShown == false`) open Welcome and save `welcomeShown = true`; menu "Show Welcome" → `showWelcome()`.
  - `--demo-overlay`: shows the overlay with `.keyboardBacklight`, 0.5 (for screenshots).

- [ ] **Step 1: Write the overlay and Welcome** — Interfaces block.
- [ ] **Step 2: Live verification** — Run: `make install && open ~/Applications/trrek.app --args --welcome && sleep 2 && screencapture -x /tmp/trrek-welcome.png`; `open ~/Applications/trrek.app --args --demo-overlay && sleep 1 && screencapture -x /tmp/trrek-overlay.png` — Expected: the window and overlay are in the screenshots; the overlay disappears after 1 s.
- [ ] **Step 3: make check and commit** — `feat(app): add level overlay and welcome window`; branch `feat/app-overlay-welcome`; CHANGELOG line.

---

### Task 6: Release preparation — manual test list, performance, maintenance and v0.1.0

**Files:**
- Create: `docs/testing.md`
- Modify: `README.md` (install, permission, feature list, performance measurement), `CHANGELOG.md` (`## [0.1.0] - <date>`), `.github/dependabot.yml` (`groups: github-actions: patterns: ["*"]`), `Makefile` (`install`: `mkdir -p ~/Applications`), `scripts/perf.sh` (warn and exit if a running instance exists; explicit error on an empty RSS reading), `scripts/build-app.sh` (`--version`/`--build` format validation)
- Modify: `Sources/TrrekEngine/Version.swift` (`"0.1.0"`)

- [ ] **Step 1: Manual test list** — `docs/testing.md` (Turkish): each edge (volume, brightness, app switching, keyboard backlight, media), corners, middle click, precision, cursor freeze, scroll suppression, typing gate, Hold/Toggle, pause in app, after sleep, device plug-in, settings window tabs, welcome, overlay, Accessibility not granted state, Reset to Defaults, Launch at Login. For each item "How" and "Expected".
- [ ] **Step 2: Maintenance fixes** — Makefile, perf.sh, build-app.sh, dependabot grouping.
- [ ] **Step 3: Performance measurement** — Run: `make install && scripts/perf.sh` — Expected: `RSS < 15360 KB`, `CPU 0.0`; write the values to the README "Performance" section.
- [ ] **Step 4: Release notes** — CHANGELOG `Unreleased` → `0.1.0`; README feature list and install (`make install`, right click › Open, Accessibility).
- [ ] **Step 5: Commit and PR** — `chore(release): prepare 0.1.0`; branch `chore/release-0.1.0`; after merge `git tag v0.1.0 && git push origin v0.1.0` → `release.yml` runs; Run: `gh release view v0.1.0` — Expected: `trrek-v0.1.0.zip` and `.dmg` attached.

---

## Self-review notes

- Spec coverage: 6.2 (pipeline) / 6.3 / 6.4 / 6.5 Tap B / 6.6 → Task 1; 6.5 Tap A / 6.7 Path B / 6.10 → Task 2; 7.1 / 7.2 / 7.4 / 7.7 / 7.8 (app side) → Task 3; 7.3 → Task 4; 7.5 / 7.6 → Task 5; 9.3 / 9.4 / 10.5 / 11 end of Phase 1 → Task 6. 6.8 and 6.9 (Phase 2) are not in this plan.
- Small items carried over from the previous plan: `onFrame @Sendable`, device list accumulation, `TrrekProbe` explicit dependency, `EventTapGuard` main thread, HID tap location → Task 1; `make install` mkdir, perf.sh guards, build-app.sh validation, dependabot grouping → Task 6.
- Review Focus tests: 2 → Task 3; 3 → Task 1; 4 → Task 3; 5 → Task 2; 1 manual test (hardware).
