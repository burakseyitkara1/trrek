# trrek — Design Specification

Date: 2026-11-03 · Status: approved (autonomous execution)

## 1. Purpose and scope

**trrek** is a menu bar app for macOS that turns the trackpad edges and corners into one-finger controls. It is for personal use, is free, and is written from scratch in this repository.

**Product definition**
- Right edge, slide up/down → volume. Left edge → screen brightness (on external displays with DDC/CI, optional).
- Top edge, slide left/right → app switching (the system's ⌘-Tab switcher is driven). Bottom edge → keyboard backlight; media on a Mac without a backlight.
- Options for the top and bottom edge: Switch Apps, Scrub Video, Keyboard Backlight, Media, Off.
- Double tap on the corners → Off, Mute or Screenshot (⌘⇧5). Three-finger tap → middle click (optional).
- A haptic tick on every step (Off/Light/Medium/Strong), the system's own volume/brightness HUD, a fixed cursor while sliding, precision mode (quarter step), edge width (Narrow/Standard/Wide), bottom quarter mode, swapping sides, a Hold-to-Slide key (Hold/Toggle), per-app pausing, palm rejection, ignoring touches while typing, automatic recovery after sleep, launch at login.
- SwiftUI windows in the macOS 26 Liquid Glass design language for settings and welcome; quick switches in the menu bar.

**Goals**
- Minimum resource use: 0% CPU at idle, memory under 15 MB, constant-time work per frame, no heap allocation.
- A gesture engine that can be tested in CI without hardware.
- A build that does not need Xcode (Swift Package Manager + scripts).
- A professional, autonomously executed development process with PR and CI discipline from start to finish.

**Out of scope:** License, trial, payment and automatic update mechanisms; a website; notarization; Intel; before macOS 26.

**Success criteria**
1. On the development Mac (macOS 27.2) the four edges, four corners and three-finger middle click work as defined; the system HUD is visible for volume and brightness; a haptic tick is felt on every step.
2. `make perf` reports 0 CPU at idle and memory under 15 MB.
3. The Engine tests cover every rule in Section 5 and pass in CI.
4. With `make install` the app is installed to ~/Applications and opens at login; the settings window and welcome have the Liquid Glass look.
5. Every change enters main through PR, CI and review steps; the `v0.1.0` tag produces a DMG as a Release.

## 2. Environment and constraints

| Topic | Value |
|---|---|
| Development machine | Development Mac (Apple silicon), macOS 27.2, Force Touch trackpad (Multitouch ID `<multitouch-id>`), has a keyboard backlight, built-in display only |
| Tools | Command Line Tools, Swift 6.4.2, Homebrew; no Xcode |
| CI runner | `macos-26` image: macOS 26.6.1, Xcode 26.6, SwiftLint 0.65, SwiftFormat 0.62 |
| Swift compatibility | `swift-tools-version: 6.0`, Swift 6 language mode; no Swift 6.3+ language features and no macOS 27 APIs |
| Target platform | macOS 26.0+, arm64 only |
| GitHub | Repository `burakseyitkara1/trrek` (public, MIT; the private repository before it was opened is archived as `trrek-private`). Releases are also in the `burakseyitkara1/trrek-releases` repository. Enforcement with local tools (Section 10) |
| macOS runner budget | ~200 macOS minutes per month (2000 × 1/10). CI runs only on PRs and release tags; round-trip target under 4 min |
| Private API | MultitouchSupport, CoreBrightness, IOAVService, MediaRemote. Sandbox off. Every symbol is resolved with `dlsym`; if missing the feature turns off |

## 3. Architecture overview

Three layers, one process, one-way dependency:

```
Trrek (AppKit + SwiftUI)  →  TrrekPlatform (private API bridges)  →  TrrekEngine (pure Swift)
```

- **TrrekEngine** makes no system calls. It takes a `Frame` and produces `GestureCommand`s. It depends only on Foundation and, for its own lock, the `os` module.
- **TrrekPlatform** implements the Engine's protocols with real APIs: the multitouch source, haptics, key and mouse event posting, event taps, keyboard backlight, DDC, Now Playing, system notifications.
- **Trrek** connects the two: settings, menu, settings window, overlay, welcome, permissions, lifecycle.

**Thread model**
- Multitouch frames arrive on the framework's own background thread. The Platform layer converts the frame to a `Frame` on the stack and calls the Engine synchronously.
- Every public method of the Engine (`process`, `tick`, `update`, host signals, `reset`, `stateKind`) runs under the Engine's own `OSAllocatedUnfairLock`; calls from different threads are serialized by this lock. It is not a problem for the host to hold its own lock as well. The sink is called while the lock is held and must not call back into the Engine.
- Clock contract: all times in the Engine are system uptime seconds (`ProcessInfo.processInfo.systemUptime`, the same clock as `Frame.timestamp`). CGEvent timestamps are given divided by 1e9.
- The Engine gives commands to a synchronous sink. The sink does CGEvent posting, haptics and tap enable/disable on the same thread (all thread-safe). Menu and overlay updates go to the main thread with `DispatchQueue.main.async`.
- Event tap callbacks run on the main run loop and call the host signals (`noteKeyDown`, `setHoldKeySatisfied`); these calls are serialized with the frames by the Engine's own lock.
- There is no periodic timer. There are two one-shot timers: the slide watchdog (while a slide is in progress, re-armed on every frame) and overlay hiding (while the overlay is visible).
- While a slide is in progress `ProcessInfo.beginActivity(.userInitiated)` is held; it is released when it ends. App Nap is allowed at idle.
- SwiftUI windows (Settings, Welcome) are in memory only while open; when closed the hosting controller and window are released.

## 4. Package structure

```
trrek/
├── Package.swift
├── Makefile · CLAUDE.md · README.md · CHANGELOG.md · LICENSE (MIT)
├── .swiftlint.yml · .swiftformat
├── Sources/
│   ├── TrrekEngine/
│   │   ├── Types.swift          # Touch, Frame, TouchBuffer, DeviceGeometry, Edge, Corner, Zone
│   │   ├── Config.swift         # EngineConfig, Thresholds, EdgeAction, CornerAction
│   │   ├── Commands.swift       # GestureCommand, HapticEvent, CommandSink
│   │   ├── Geometry.swift       # zone detection, mm conversions
│   │   └── GestureEngine.swift  # state machine
│   ├── TrrekPlatform/
│   │   ├── PrivateSymbols.swift # all dlopen/dlsym definitions, a single file
│   │   ├── Multitouch/MultitouchSource.swift
│   │   ├── Haptics/ActuatorHaptics.swift
│   │   ├── Input/MediaKeyPoster.swift · KeyPoster.swift · MousePoster.swift · EventTapGuard.swift · EventStamp.swift
│   │   ├── Keyboard/KeyboardBacklight.swift
│   │   ├── Display/ExternalBrightness.swift · DisplayLocator.swift      (Phase 2)
│   │   ├── Media/NowPlayingBridge.swift + Resources/nowplaying-helper   (Phase 2)
│   │   └── System/FrontmostObserver.swift · WakeObserver.swift · Permissions.swift · LaunchAtLogin.swift
│   ├── Trrek/
│   │   ├── main.swift · AppDelegate.swift · Coordinator.swift
│   │   ├── Settings.swift · SettingsStore.swift
│   │   ├── Menu/StatusMenu.swift
│   │   ├── UI/SettingsWindow.swift · SettingsView.swift · EdgesTab.swift · CornersTab.swift · GeneralTab.swift · AdvancedTab.swift
│   │   ├── UI/TrackpadDiagram.swift · WelcomeWindow.swift · WelcomeView.swift · OverlayPanel.swift · OverlayView.swift
│   │   └── Resources/MenuIcon.pdf
│   └── TrrekProbe/main.swift    # development tool, not in the .app
├── Tests/TrrekEngineTests/
├── Resources/AppIcon.icns · Info.plist.in · icon-1024.png
├── scripts/build-app.sh · make-icon.sh · install-hooks.sh · perf.sh
├── docs/superpowers/specs/ · docs/superpowers/plans/ · docs/testing.md
└── .github/workflows/ci.yml · release.yml · dependabot.yml · PULL_REQUEST_TEMPLATE.md
```

`Package.swift`: platform `.macOS("26.0")`; targets `TrrekEngine` (library), `TrrekPlatform` (library, depends on Engine), `Trrek` (executable, depends on Platform), `TrrekProbe` (executable, depends on Platform), `TrrekEngineTests` (test, Swift Testing). No external package dependencies. Private frameworks are not linked, they are `dlopen`ed at run time.

## 5. TrrekEngine

### 5.1 Data types

```swift
public struct Touch { id: Int32; x: Float; y: Float; majorAxisMM: Float }   // x,y normalized 0...1, origin bottom left
public struct TouchBuffer { count: Int; storage: (Touch × 16) }               // fixed capacity, no heap
public struct DeviceGeometry { widthMM: Float; heightMM: Float; isBuiltIn: Bool }
public struct Frame { deviceID: UInt64; timestamp: TimeInterval; geometry: DeviceGeometry; touches: TouchBuffer }
public enum Edge { left, right, top, bottom }
public enum Corner { topLeft, topRight, bottomLeft, bottomRight }
public enum Zone { edge(Edge), corner(Corner), none }
```

The Platform puts only touches in contact into the `Frame`. An id disappearing from a frame means lift-off. More than 16 touches are truncated.

### 5.2 Configuration

```swift
public enum EdgeAction { volume, brightness, switchApps, scrubVideo, keyboardBacklight, media, off }
public enum CornerAction { off, mute, screenshot }
public struct Thresholds {           // initial values; tuned in the Phase 0 spike
  edgeWidthMM: Float = 10            // Narrow 7 · Standard 10 · Wide 14
  slideStartMM: Float = 3            // along the edge axis
  abortPerpendicularMM: Float = 4    // movement this far perpendicular to the edge before the slide starts → Spent
  stepMM: Float = 3.75               // volume, brightness, keyboardBacklight (16 steps ≈ 60 mm)
  appSwitchStepMM: Float = 12
  scrubStepMM: Float = 6             // step = 5 seconds
  mediaSkipStepMM: Float = 20
  tapMaxDuration: TimeInterval = 0.25
  tapMaxMoveMM: Float = 2
  doubleTapWindow: TimeInterval = 0.35
  lostTimeout: TimeInterval = 0.18
  threeFingerSettle: TimeInterval = 0.10
  threeFingerMaxDuration: TimeInterval = 0.30
  palmMajorAxisMM: Float = 20
  typingGate: TimeInterval = 0.40
}
public struct EngineConfig {
  left, right, top, bottom: EdgeAction      // defaults: brightness, volume, switchApps, keyboardBacklight
  topLeft, topRight, bottomLeft, bottomRight: CornerAction   // default: off
  bottomQuarterOnly: Bool = false
  precision: Bool = false
  freezeCursor: Bool = true
  middleClickEnabled: Bool = false
  holdKeyRequired: Bool = false
  thresholds: Thresholds
}
```

Swap Sides is applied in the app layer by swapping the `left`/`right` actions; the Engine keeps no separate flag. (In Phase 3 Swap Sides was removed and the action lists were extended; see 5.9.)

### 5.3 Geometry

- mm conversion: `dxMM = Δx · widthMM`, `dyMM = Δy · heightMM`.
- Edge strips: `left: x·W < w`, `right: (1−x)·W < w`, `bottom: y·H < w`, `top: (1−y)·H < w` (w = edgeWidthMM).
- Corner: the intersection of two strips; always a `corner` zone. A finger starting in a corner is bound to the neighboring edge according to its movement axis (5.4); if the corner action is Off, a double tap does nothing.
- When `bottomQuarterOnly` is on, the left/right strips produce an edge zone only when `y < 0.25`. The option restricts only vertical edge slides, not corner detection: at `y ≥ 0.25` the vertical strip still forms a corner with a horizontal strip. If such a corner candidate is bound to the vertical edge (`y0 ≥ 0.25`) the slide does not start, the candidate goes to `spent`; binding to the horizontal edge is not affected.
- Edges whose action is `off` do not count as a plain edge zone. The strips are determined by geometry; the intersection of two strips stays a corner even if one or both of its edges are `off` (its double tap works, a slide toward the `off` edge does not start; decision 48).
- Edge axis and direction: left/right → y axis, up = +1. top/bottom → x axis, right = +1.

### 5.4 State machine

A single state, shared by all devices. While in a state other than `Idle`, frames coming from another device are ignored.

| State | Data |
|---|---|
| `idle` | — |
| `candidate` | zone, touchID, x0, y0, t0 |
| `sliding` | edge, action, touchID, origin (mm), accumulatedMM, stepsEmitted, lastFrameTime |
| `lost` | sliding data, since |
| `spent` | firstDownTime, initial positions |
| `threeFinger` | ids[3], tDown, maxMoveMM |

Transitions (per frame; the gates are applied first in the order in Section 5.6):

1. **idle**
   - 1 touch, zone ≠ none → `candidate`.
   - 3 touches, all landed within `threeFingerSettle`, `middleClickEnabled` → `threeFinger`.
   - 1 touch, zone = none or 2 touches → `spent` (the first landing time and initial positions are stored).
2. **candidate**
   - touch count ≠ 1 → `spent` (if it rises to 3, the three-finger rule in `spent` is applied in the same frame).
   - |Δ| along the edge axis ≥ `slideStartMM` → `sliding`; emit `freezeCursor(true)` (if config.freezeCursor) and `haptic(.start)`. If the zone is a corner the edge is chosen by the movement axis: horizontal movement → that corner's top/bottom edge, vertical movement → the left/right edge; if the chosen edge's action is `off` → `spent`.
   - |Δ| on the perpendicular axis ≥ `abortPerpendicularMM` → `spent`.
   - lift-off, duration ≤ `tapMaxDuration` and movement ≤ `tapMaxMoveMM` → tap: if a corner, the double tap counter (same corner, second tap within `doubleTapWindow` → `mute`/`screenshot` + `haptic(.tap)`); if the edge action is `media`, double tap → `mediaPlayPause`. → `idle`.
   - lift-off, other → `idle`.
3. **sliding**
   - touch count ≥ 2 → finish(cancel) → `spent`.
   - on every frame `accumulatedMM += Δ(edge axis)`; as long as `|accumulatedMM| ≥ stepMM(action)`, emit one step command + `haptic(.step)` and decrease `accumulatedMM`. Step commands: `stepVolume(±1, fine)`, `stepBrightness(±1, fine)`, `stepKeyboardBacklight(±1, fine)`, `appSwitchStep(±1)`, `scrubStep(±1)`, `mediaNext`/`mediaPrevious`. `fine = config.precision`.
   - if `accumulatedMM` is not finite (an infinite or NaN coordinate) the slide ends with finish(cancel) → `spent`; no step is produced. At most 64 steps per frame (`maxStepsPerFrame`) are produced; if the limit is reached the remaining distance is discarded (`accumulatedMM = 0`), so a corrupt coordinate does not keep producing steps in later frames.
   - the touch id disappeared from the frame (lift-off or a momentary drop; the two cannot be distinguished) → `lost`. Verified with the spike: at lift-off the device sends state 5→6→7 and then a frame with zero touches; since the platform passes only state 3/4, the finger disappears at state 5.
   - no frame arrived (watchdog `tick(now)` with `now − lastFrameTime ≥ lostTimeout`) → finish(commit) → `idle`.
4. **lost**
   - the same id came back, within `lostTimeout` → `sliding`.
   - `lostTimeout` expired (by frame or `tick`) → finish(commit) → `idle`.
5. **spent** — if the touch count has risen to 3, ≤ `threeFingerSettle` has passed since the first landing, none has moved more than `tapMaxMoveMM` and `middleClickEnabled` → `threeFinger`. When all touches lift → `idle`.
6. **threeFinger**
   - any touch moved more than `tapMaxMoveMM` or duration > `threeFingerMaxDuration` → `spent`.
   - a fourth touch → `spent`.
   - all three lifted → emit `middleClick` + `haptic(.tap)` → `idle`.

**finish(commit/cancel):** `switchApps` → `appSwitchCommit` (`appSwitchCancel` on cancel); `scrubVideo` → `scrubCommit` (`scrubCancel` on cancel); others produce no command. If `frozen`, `freezeCursor(false)`.

### 5.5 Action mapping

| EdgeAction | Step distance | +1 command | −1 command | On release |
|---|---|---|---|---|
| volume | stepMM | stepVolume(+1) | stepVolume(−1) | — |
| brightness | stepMM | stepBrightness(+1) | stepBrightness(−1) | — |
| keyboardBacklight | stepMM | stepKeyboardBacklight(+1) | stepKeyboardBacklight(−1) | — |
| switchApps | appSwitchStepMM | appSwitchStep(+1) | appSwitchStep(−1) | appSwitchCommit |
| scrubVideo | scrubStepMM | scrubStep(+1) (+5 s) | scrubStep(−1) | scrubCommit |
| media | mediaSkipStepMM | mediaNext | mediaPrevious | — (double tap → mediaPlayPause) |

### 5.6 Gates (on every frame, in order)

1. **Palm filter:** touches with `majorAxisMM > palmMajorAxisMM` are removed from the frame; the rest are processed.
2. **Typing gate:** if `now − lastKeyDown < typingGate`, no new gesture starts in the `idle` and `candidate` states (an existing `sliding` continues).
3. **Hold-to-Slide:** if `holdKeyRequired && !holdKeySatisfied`, no new gesture starts; if the key is released during `sliding`, finish(commit).
4. **Pause:** if `paused`, any state other than `idle` returns to `idle` and frames are ignored.

### 5.7 Commands

```swift
public enum HapticEvent { start, step, tap, limit }
public enum GestureCommand {
  case stepVolume(Int, fine: Bool), stepBrightness(Int, fine: Bool), stepKeyboardBacklight(Int, fine: Bool)
  case appSwitchStep(Int), appSwitchCommit, appSwitchCancel
  case scrubStep(Int), scrubCommit, scrubCancel
  case mediaPlayPause, mediaNext, mediaPrevious
  case mute, screenshot, middleClick
  case haptic(HapticEvent), freezeCursor(Bool)
}
public protocol CommandSink: AnyObject { func handle(_ command: GestureCommand, device: UInt64) }
```

The `limit` haptic event is produced by the platform only for actions whose level is known (keyboardBacklight in Path B, DDC); the Engine does not produce it.

### 5.8 Host interface

```swift
public final class GestureEngine {
  init(config: EngineConfig, sink: CommandSink)
  func update(config: EngineConfig)        // takes effect immediately; sliding/lost → finish(commit), candidate → spent
  func process(_ frame: Frame)              // the Engine takes its own lock
  func tick(now: TimeInterval)             // watchdog
  func noteKeyDown(at: TimeInterval)
  func setHoldKeySatisfied(_: Bool)
  func setPaused(_: Bool)
  func reset()                              // sliding/lost → finish(cancel); return to idle
}
```

`reset()` means cancel: `switchApps` → `appSwitchCancel`, `scrubVideo` → `scrubCancel`, then `freezeCursor(false)` if the cursor is frozen, then `idle`; the pending double tap record is deleted. `update(config:)` keeps the commit meaning; a finger that is a `candidate` at that moment drops to `spent` and produces no gesture until it lifts. The double tap record is deleted every time the Engine enters the `spent` or `threeFinger` state.

### 5.9 Edge and corner actions, sensitivity (Phase 3)

All four edges offer the same list: `volume`, `brightness`, `keyboardBacklight`, `switchApps`, `switchTabs`, `switchDesktops`, `scrubVideo`, `media`, `zoom`, `undoRedo`, `off`. `Settings` keeps `leftEdge` (default `brightness`) and `rightEdge` (default `volume`) for the left and right edge; Swap Sides was removed. An old `swapSides: true`, if `leftEdge`/`rightEdge` are missing, is read as left=`volume`, right=`brightness` and is not written again (decision 44). When the keyboard backlight bridge is missing `keyboardBacklight` falls back to `media` on every edge.

| EdgeAction | Step distance | +1 command (sent) | −1 command (sent) | On release |
|---|---|---|---|---|
| switchTabs | tabSwitchStepMM = 12 | tabSwitchStep(+1) (⌃⇥) | tabSwitchStep(−1) (⌃⇧⇥) | — |
| switchDesktops | desktopSwitchStepMM = 20 | desktopSwitchStep(+1) (⌃→) | desktopSwitchStep(−1) (⌃←) | — |
| zoom | zoomStepMM = 8 | zoomStep(+1) (⌘=) | zoomStep(−1) (⌘−) | — |
| undoRedo | undoRedoStepMM = 10 | undoRedoStep(+1) (⇧⌘Z) | undoRedoStep(−1) (⌘Z) | — |

The +1 direction is the axis rule in 5.3: right on a horizontal edge, up on a vertical edge. While trrek's own window is in front, `switchTabs`, `zoom` and `undoRedo` steps (like scrub) are not sent; `switchDesktops` is system-wide and works. `switchApps` and `keyboardBacklight` behave the same whichever edge they are assigned to (holding ⌘, commit/cancel; the overlay and limit haptic are in the dispatcher).

`CornerAction`: `off`, `mute`, `screenshot`, `playPause` (`mediaPlayPause`), `missionControl`, `appWindows`, `showDesktop`, `spotlight` (⌘Space), `lockScreen` (⌃⌘Q), `screenshotArea` (⇧⌘4). Mission Control, app windows and show desktop open the system's Mission Control app through the `MissionControlOpening` port with no argument, `2` and `1`; if the app cannot be found the error is written to the log (decision 46).

**Sensitivity:** `Settings.slideSensitivity` (`veryLow` 1.6 · `low` 1.25 · `standard` 1.0 · `high` 0.8 · `veryHigh` 0.6). `ConfigMapper` scales all step distances by this multiplier; the other thresholds do not change (decision 47). The setting is the "Slide Sensitivity" picker in the General tab. Without the Accessibility permission all the new actions are off (decision 27).

## 6. TrrekPlatform

### 6.1 Symbol loading policy

`PrivateSymbols.swift` contains all `dlopen`/`dlsym` calls. Every symbol is `lazy static` and optional. A bridge returns `isAvailable = true` if all the symbols it needs are resolved. A symbol that cannot be resolved is logged, the feature turns off, no crash. Direct `extern` linking is not used because of arm64e pointer authentication.

### 6.2 MultitouchSource

- Framework: `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`.
- Symbols: `MTDeviceCreateList`, `MTDeviceIsBuiltIn`, `MTDeviceGetSensorSurfaceDimensions`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceRelease`.
- Startup: the list is obtained, the surface size is read for each device (unit 1/100 mm; verified in the spike: built-in trackpad 12194×7408 → 121.94×74.08 mm), the callback is registered, `MTDeviceStart(dev, 0)`.
- Callback signature: `(MTDeviceRef, UnsafePointer<MTTouch>, Int32 count, Double timestamp, Int32 frame)`. `MTTouch` is a 96-byte C struct: `frame:Int32, timestamp:Double, identifier:Int32, state:Int32, fingerID:Int32, handID:Int32, normalizedPosition{x,y}:Float, normalizedVelocity{x,y}:Float, total:Float, pressure:Float, angle:Float, majorAxis:Float, minorAxis:Float, absolutePosition{x,y}:Float, absoluteVelocity{x,y}:Float, reserved:Int32×2, density:Float`. State values: 3 = contact started, 4 = contact continuing; the others are not contact. The layout is verified with `TrrekProbe layout-check`.
- Sanity check on the first frame: if `normalizedPosition` is not within 0...1 and `majorAxis` not within 0...100 mm, the source is stopped and a `layoutMismatch` error is published.
- Frame conversion: only touches with state ∈ {3, 4} are written to the `TouchBuffer`; `majorAxisMM = majorAxis`. The integer value of the `MTDeviceRef` pointer is used as `deviceID`.
- Restart: `stop()` + `start()` on the `WakeObserver` wake notification and on device add/remove with IOKit `IOServiceAddMatchingNotification("AppleMultitouchDevice")`.
- Watchdog: while a slide is in progress, a `DispatchSourceTimer` (one-shot, `lostTimeout`) is re-armed on every frame; when it fires, `engine.tick(now:)`.

### 6.3 ActuatorHaptics

- Symbols: `MTActuatorCreateFromDeviceID(UInt64)`, `MTActuatorOpen`, `MTActuatorActuate(actuator, Int32 waveform, UInt32 0, Float 0, Float 0)`, `MTActuatorClose`.
- Device ID: the `Multitouch ID` from the IORegistry `AppleMultitouchDevice` entries; the one with `MT Built-In == true` is built-in, the others are external. The actuator of whichever device the slide came from (`MTDeviceIsBuiltIn`) is used; if there is no match, the first actuator.
- Strength mapping (initial; tuned in the spike): Light → 4, Medium → 5, Strong → 6; with Strong, `start`/`tap` events are two pulses (60 ms apart). Off → nothing.
- Fallback: if there is no actuator, `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)`.

### 6.4 MediaKeyPoster

- Event: `NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (0x0A << 8), data2: -1)` followed by the `0x0B` (key up) version of the same event; `event.cgEvent?.post(tap: .cghidEventTap)`.
- Key codes: SOUND_UP 0, SOUND_DOWN 1, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3, MUTE 7, PLAY 16, NEXT 17, PREVIOUS 18, ILLUMINATION_UP 21, ILLUMINATION_DOWN 22.
- `fine == true` → `modifierFlags = [.option, .shift]` (quarter step).
- `EventStamp`: all events are sent with `CGEventSource(stateID: .privateState)` and stamped with `userData = 0x7472726B` ("trrk"); when the taps see this stamp they ignore the event (our own events do not trigger the typing gate).

### 6.5 EventTapGuard

- **Tap A** (always on): `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .listenOnly, [keyDown, flagsChanged])`. keyDown → `engine.noteKeyDown`. flagsChanged → Hold-to-Slide evaluation (6.10).
- **Tap B** (only during a slide): at the `.cghidEventTap` location (the event is swallowed before it reaches WindowServer, the cursor stays in place), `.defaultTap`, `[mouseMoved, leftMouseDragged, rightMouseDragged, otherMouseDragged, scrollWheel]`. While on, scrollWheel is always swallowed; mouseMoved/dragged are swallowed only if `freezeCursor` is on. The `freezeCursor(true)` command calls `CGEvent.tapEnable(tap, true)`, `freezeCursor(false)` turns it off. Zero cost while the tap is off.
- If `tapDisabledByTimeout`/`tapDisabledByUserInput` arrives the tap is re-enabled.
- Without Accessibility the taps are not created; `isAvailable = false`.

### 6.6 KeyPoster and MousePoster

- **Switch Apps protocol:** the first `appSwitchStep` → ⌘ keyDown (`flagsChanged`, keycode 55, flags `.maskCommand`), then Tab (keycode 48) down/up with `.maskCommand`; for `−1` `.maskCommand | .maskShift`. Later steps are only Tab. `appSwitchCommit` → ⌘ keyUp. `appSwitchCancel` → Escape (53) down/up, then ⌘ keyUp.
- **Screenshot:** keycode 23 ('5') down/up, flags `.maskCommand | .maskShift`.
- **Middle click:** `CGEvent(mouseEventSource:, mouseType: .otherMouseDown, mouseCursorPosition: NSEvent.mouseLocation (converted to CG coordinates), mouseButton: .center)`, then `.otherMouseUp`. Both to `.cghidEventTap`.
- All events are sent with the stamped source in 6.4.

### 6.7 KeyboardBacklight

Phase 0 spike result: the media key path could not be verified without the Accessibility permission; **Path B is primary**, Path A remains as a trial once permission is obtained.
- **Path A (later):** ILLUMINATION_UP/DOWN media key events; if macOS shows its own HUD this path can be switched to, the bridge returns `nativeHUD = true`.
- **Path B (primary):** the CoreBrightness `KeyboardBrightnessClient` class (`copyKeyboardBacklightIDs`, `brightnessForKeyboard:`, `setBrightness:fadeSpeed:commit:forKeyboard:`), step 1/16, 1/64 if `fine`; the level is shown in the overlay; `haptic(.limit)` at 0 and 1.
- If the bridge's `isAvailable == false` the Keyboard Backlight option is grayed out in settings and the bottom edge default falls back to Media.

### 6.8 ExternalBrightness and DisplayLocator (Phase 2)

- `DisplayLocator`: the cursor position is taken from the position of an event created without a source (`CGEvent(source: nil).location`, global display coordinates) and converted to a `CGDirectDisplayID` with `CGGetDisplaysWithPoint`; if `CGDisplayIsBuiltin` it is built-in.
- Built-in → `stepBrightness` through the media key path. External and the setting on → DDC. An external display for which no DDC service was found in the last scan (such as a wireless/virtual display) does not count as external and uses the media key path (decision 35).
- DDC/CI: the `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C` symbols; 7-bit address 0x37, data address 0x51, VCP code 0x10 (brightness); the packet is built according to the DDC checksum standard. The external `DCPAVServiceProxy` entries in the IORegistry are matched to displays first by EDID manufacturer/model/serial number (then, if the serial number is missing, by manufacturer/model); displays that do not match take the remaining services in order. The scan is done in the background while it is being created and after every display reconfiguration. At the start of a slide the current/max value is read, `max/16` (fine: `max/64`) is written on every step, and the overlay shows the percentage.
- If one of the symbols is missing the bridge is not created; the setting in the Edges tab is disabled with the "Not available on this Mac" note.
- It cannot be verified on this Mac; it is marked "best effort". If a transfer error occurs on a display that has a service the overlay shows "No DDC" (no bar); the error is written to the log once on each entry into the error state.

### 6.9 Scrub Video (arrow keys)

- Video scrubbing is done by sending ←/→ arrow keys to the front app (decision 33): `scrubStep(+1)` → right arrow (keyCode 124), `scrubStep(−1)` → left arrow (123), no flags. Browsers and most players scrub with these keys; no extra process or private API is needed.
- The step size is determined by the app; the overlay label assumes 5 s per step. `CommandDispatcher` keeps the net step count per slide and shows `"+15 s"` / `"−10 s"` / `"0 s"` in the overlay (icon + label, no level bar).
- `scrubCommit` and `scrubCancel` only reset the counter; they send no key (the steps have already been applied).
- If the front app is trrek itself (the settings or welcome window) the steps send no key and are not counted (decision 35).
- Since it sends synthetic events it is off without the Accessibility permission (decision 27).

### 6.10 System bridges

- **FrontmostObserver:** `NSWorkspace.didActivateApplicationNotification` → bundle id; if it is in `Settings.pausedBundleIDs`, `engine.setPaused(true)`.
- **WakeObserver:** `NSWorkspace.didWakeNotification` → `MultitouchSource.restart()`.
- **Permissions:** `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`; the state is refreshed with the `DistributedNotificationCenter` `com.apple.accessibility.api` notification, and the taps are created at that moment. No timer.
- **LaunchAtLogin:** `SMAppService.mainApp.register()` / `unregister()`; the state is read from `status`.
- **Hold-to-Slide:** Tap A flagsChanged → is the selected modifier down? In *Hold* mode `setHoldKeySatisfied(isDown)`. In *Toggle* mode if the modifier is pressed alone and released within 300 ms (no other key in between) the state is flipped; the state is shown with a small dot on the menu bar icon.

## 7. Trrek (the app)

### 7.1 Lifecycle

1. `SettingsStore.load()` (corrupt data → defaults + log).
2. `Permissions.check()`; if there is no permission, Welcome opens and the "Grant Accessibility…" item appears in the menu.
3. `Coordinator` connects the Engine, the Platform bridges and `Settings`; it produces `EngineConfig`.
4. `MultitouchSource.start()`; if it fails, "Trackpad not found" in the menu and a retry on wake/device notifications.
5. `EventTapGuard.install()` (if permission is granted).
6. `StatusMenu` is set up. On first run (`welcomeShown == false`) Welcome and Launch at Login registration.
7. On exit: cleanup equivalent to `appSwitchCancel` so that ⌘ does not stay held, the taps are closed, multitouch is stopped.

`Info.plist`: `LSUIElement = true`, `LSMinimumSystemVersion = 26.0`, `CFBundleIdentifier = com.burakseyitkara.trrek`, `NSHumanReadableCopyright`, `CFBundleShortVersionString` and `CFBundleVersion` from the build script.

### 7.2 Menu bar menu

The menu is for quick access; all configuration is in the settings window.

```
trrek is active            (status line, disabled; "Paused in <App>", "Accessibility access needed", "Trackpad not found")
─────────────
Precision Control          ✓ switch
Freeze Cursor              ✓ switch
Hold-to-Slide: On/Off      (only in Toggle mode; state)
Pause in <Front App>       (hidden if the front app is trrek; if paused "Resume in <App>")
─────────────
Settings…                  ⌘,
Show Welcome
Grant Accessibility…       (only when permission is missing)
─────────────
About trrek
Check for Updates…         (0.4.0)
Quit trrek                 ⌘Q
```

Since 0.4.0, if a new version is known there is an "Update Available: trrek X.Y.Z" row at the very top of the menu, with a separator, and a filled up arrow appears in the top left corner of the menu bar icon (7.4c, decision 71). The "Update Available: trrek X.Y.Z…" menu item and the download flow in the first design were changed by decision 71.

The menu is refreshed when it opens with `menuNeedsUpdate`. Icon: the `MenuIcon.pdf` template image (a trackpad silhouette, its right edge highlighted); a dot in the corner while active in Toggle mode.

### 7.3 Settings window (SwiftUI, Liquid Glass)

- Opening: from the menu "Settings…" or ⌘,. `NSWindow` + `NSHostingController<SettingsView>`; `titlebarAppearsTransparent`, toolbar style `.unified`; released when the window closes, rebuilt on the next open.
- Layout: four tabs with `TabView`; each tab is a `Form` + `.formStyle(.grouped)`. On macOS 26 the toolbar and tabs take the system's Liquid Glass look; custom items are made glassy with `.glassEffect(.regular, in: .rect(cornerRadius: 12))`. Fixed size 640×480 pt.
- **General:** Haptic Feedback (segment: Off/Light/Medium/Strong), Slide Sensitivity (Phase 3), Precision Control, Freeze Cursor, Launch at Login, Language (Phase 3; 7.4b), Export Settings…/Import Settings… (Phase 3), Reset to Defaults… button.
- **Edges:** At the top an interactive `TrackpadDiagram` (a trackpad silhouette with a glass surface; the four edges labeled with colored strips and their selected actions; in Phase 3 150 pt high in the Edges tab). Below: Left Edge, Right Edge (in Phase 3 in place of Swap Sides), Top Edge, Bottom Edge (Picker), Edge Width (segment), Bottom Quarter Only, External Monitor Brightness (disabled with an explanation if there is no bridge).
- **Corners & Taps:** A Picker for the four corners (Off/Mute/Screenshot; in Phase 3 the actions in 5.9 were added) with corner badges on the diagram; the 3-Finger Tap Middle Click switch and a hint text about the "Look up & data detectors" setting.
- **Advanced:** Hold-to-Slide Key (Picker: None/Shift/Control/Option/Command) and mode (Hold/Toggle); the Paused Apps list (per row the app icon + name, "−" removes, "+" picks an app from `NSOpenPanel`); Accessibility status and an "Open System Settings" button; version information.
- Data flow: `SettingsView` observes an `@Observable` `SettingsModel`; every change is written to `SettingsStore` and `Coordinator` applies a new `EngineConfig`. The model is not in memory while the window is not open.

### 7.4 Settings

```swift
struct Settings: Codable, Equatable {
  var schemaVersion = 1
  var hapticStrength: HapticStrength = .medium
  var edgeWidth: EdgeWidth = .standard
  var precision = false, freezeCursor = true, bottomQuarterOnly = false
  var slideSensitivity: SlideSensitivity = .standard   // Phase 3
  var externalMonitorBrightness = false
  var leftEdge: EdgeAction = .brightness              // Phase 3; the old swapSides is read only
  var rightEdge: EdgeAction = .volume
  var topEdge: EdgeAction = .switchApps
  var bottomEdge: EdgeAction = .keyboardBacklight     // .media on first run if there is no bridge
  var corners: [Corner: CornerAction] = all .off
  var middleClick = false
  var holdKey: HoldKey = .none, holdKeyMode: HoldKeyMode = .hold
  var pausedBundleIDs: [String] = []
  var launchAtLogin = true
  var welcomeShown = false
  var language: AppLanguage = .system                 // Phase 3: system, english, turkish
}
```

JSON under the `settings` key in `UserDefaults.standard`. `schemaVersion` is for future migration. Reset to Defaults: confirmation; `launchAtLogin`, `welcomeShown` and `language` are kept.

#### 7.4a Export and import (Phase 3)

`TrrekAppCore.SettingsDocument` writes and reads the settings to a `.trrek` file: indented JSON with sorted keys, `{"appVersion", "format": "trrek-settings", "formatVersion": 1, "settings": {…}}`. `launchAtLogin`, `welcomeShown` and (Phase 3, 7.4b) `language` belong to this Mac; they are not exported and on import their current values are kept. `settings` is read with the forgiving decoder. A file larger than 1 MB, not JSON, with a different `format` or `formatVersion` < 1 is a `notSettingsFile` error, a file with `formatVersion` > 1 or `settings.schemaVersion` newer than this build is a `newerFormat` error; in both the settings do not change and an alert appears. The Export/Import buttons in the General tab open the panels as sheets on the settings window; after confirmation, import goes through the `SettingsModel` → `onChange` → `Coordinator.apply` path. `Info.plist` exports the `com.burakseyitkara.trrek.settings` type (conforms to `public.json`, extension `trrek`) and opens it with the Viewer role; a file opened from Finder opens the settings window on the General tab with `application(_:open:)` and shows the same confirmation (decision 43).

#### 7.4b Language and localization (Phase 3)

Interface texts are written in English; the translations are in the `Sources/Trrek/Resources/{en,tr}.lproj/Localizable.strings` files and the key is the English source text. `build-app.sh` copies this folder to the bundle's `Contents/Resources` folder; the SwiftPM target leaves the folder out (`exclude`). `Info.plist`: `CFBundleDevelopmentRegion` `en`, `CFBundleLocalizations` `[en, tr]`; `InfoPlist.strings` translates the name of the `.trrek` type. In SwiftUI literal texts (`Text("…")`, `Button("…")` …) are translated automatically, `TrrekAppCore` and AppKit texts with `String(localized:bundle: .main)`. The overlay's "No DDC" label is looked up as a key when shown, and the unit of the scrub label ("+15 s") is translated with the `"%@ s"` format (Turkish "sn"). `Settings.language` (`system`, `english`, `turkish`) is the Language picker in the General tab; it belongs to this Mac's user, is not exported, and import and Reset keep it. When it changes the `AppleLanguages` in the app's own defaults domain is written (deleted for `system`); if the localization the selection resolves to (for `system` according to the global `AppleLanguages`) differs from the one at launch, the "Relaunch trrek to use the new language." row appears with a Relaunch button; the button starts a short shell that waits for trrek to quit and reopens the same bundle, and quits the app. If at launch the setting and the preference differ, the preference is written according to the setting (decisions 49, 50).

#### 7.4c Update check (0.4.0)

trrek reads the `releases/latest` endpoint of the public `burakseyitkara1/trrek-releases` repository (ephemeral session, only `Accept` and `User-Agent: trrek/<version>`, 15 s). The pure logic is in `TrrekAppCore`: `SemanticVersion`, `ReleaseInfo` (tag, page, `trrek-vX.Y.Z.dmg`, notes; drafts/prereleases are rejected; the DMG address must be exactly the repository's `releases/download/vX.Y.Z/trrek-vX.Y.Z.dmg` address and the page under the repository's `releases`, and the same check is made when a recorded update is read), `UpdateCheckPolicy` (manual always; automatic at most once in 24 hours, 1 hour after a failure), `UpdateStateStore` (defaults keys separate from the settings) and `UpdateChecker` (the feed is behind the `ReleaseFeed` protocol). On the app side `UpdateController` checks once as a one-shot 10 s after launch and wake, when the menu opens and manually; there is no timer. Menu: if a new version is known, a bold "Update Available: trrek X.Y.Z…" at the top (while downloading, a disabled "Downloading trrek X.Y.Z…"), and always "Check for Updates…" under About. The download goes to `~/Downloads/trrek-vX.Y.Z.dmg` (the first time the system asks for permission with the `NSDownloadsFolderUsageDescription` description), is quarantined and opened (if the quarantine cannot be written it is only shown in Finder); an error, including a permission denial, offers "Open Download Page". When the automatic check first finds a new version it sends a single notification (the permission is requested when first needed); clicking downloads. General: "Check for Updates Automatically" (`Settings.checkForUpdatesAutomatically`, exported), Check Now and the last check time. `--assume-version X.Y.Z` changes only the version the checker compares. `release.sh` also publishes the same DMG/zip to this repository with the CHANGELOG section (decisions 52–64).

*The menu item, Downloads, notification and "Open Download Page" flow above is the first design; before 0.4.0 was released it changed with decisions 65–72 as follows:* a known update is shown with a filled up arrow in the top left corner of the icon and with a row with a custom view at the top of the menu ("Update Available: trrek X.Y.Z"); there is no notification, Downloads is not touched (no `NSDownloadsFolderUsageDescription`). Clicking the row starts the update without closing the menu: the row becomes "Downloading trrek X.Y.Z…" (determinate progress), "Installing trrek X.Y.Z…" in place; the DMG goes to `~/Library/Caches/com.burakseyitkara.trrek/Updates`, its signature is checked and it is mounted hidden and read-only, the app is copied and its Developer ID signature, notarization, identity and version are verified, it is re-verified right before and after the swap and replaced in place, and relaunched without asking for confirmation. An error makes the row "Update Failed — Try Again"; if trrek cannot replace itself the release page opens in the browser ("Update in Browser…"). A manual check shows an alert only when up to date or on failure; General shows the same state with an Update Now button. The states are in `TrrekAppCore.UpdateRowState`, the install is in `UpdateInstaller`.

### 7.5 OverlayPanel

- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = true`, `hasShadow = false`.
- Content: `NSHostingView<OverlayView>`; the SwiftUI view with `.glassEffect(.regular, in: .capsule)` an SF Symbol icon + a 16-segment level bar + percentage; for labeled values (scrub time, "No DDC") there is no bar and the label takes its natural width (decision 35).
- Position: top right of the display where the cursor is, 16 pt margin, 240×56 pt (widened from 220 so that the percentage row and the widest labels fit).
- Use: keyboardBacklight Path B, DDC, Scrub Video. Created on first need; hidden 1.0 s after the last update (one-shot `DispatchWorkItem`).

### 7.6 Welcome window (SwiftUI, Liquid Glass)

`NSWindow` + `NSHostingController<WelcomeView>`, 560×440 pt, no toolbar, system material background. Content: a title, `TrackpadDiagram` (the same component, read-only), glass cards describing the four edges (icon + one line), the Accessibility status and a "Grant Accessibility Access" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), "Open Settings" and "Done". In Phase 2 the cards appear one after another (a light animation).

### 7.7 Logging

`os.Logger(subsystem: "com.burakseyitkara.trrek", category:)`; categories `engine`, `platform`, `app`. No logging per frame. Symbol resolution results, device startup, permission state and errors at the `info`/`error` level.

### 7.8 Packaging

- `scripts/build-app.sh [--version X.Y.Z] [--build N]`: `swift build -c release --arch arm64`, the `dist/trrek.app` tree, the binary, variable substitution in `Info.plist.in`, `AppIcon.icns`, resources, `codesign --force --sign - --deep`.
- `scripts/make-icon.sh`: `Resources/icon-1024.png` → sizes with `sips` → `iconutil` → `AppIcon.icns`. The 1024 px source image is produced from CoreGraphics with `scripts/render-icon.swift` (a trackpad silhouette with a glass surface, its right edge bright).
- `make install`: `dist/trrek.app` → `~/Applications/trrek.app`, registered with `lsregister`.
- `TrrekProbe` is not packaged.

## 8. Error handling

| Situation | Behavior |
|---|---|
| Private symbol missing | The bridge `isAvailable=false`; the related setting is disabled; log `error` |
| MTTouch layout not sane | If on the first frame of a device that contains a contact the normalized position is outside -0.05…1.05 or not finite, or majorAxis is outside 0…100, the source immediately drops frames and stops on the main thread; the menu status line "Trackpad data unavailable"; log. Later frames are not checked. It retries on wake and device notifications |
| A multitouch device that is not a trackpad (e.g. a mouse with a touch surface) | It is not taken into the stream, produces no gestures and does not count for "trrek is active". The kind is determined from the generic HID properties in the I/O Registry (`HIDPointerAccelerationType`, `DeviceUsagePairs`); if neither is present the device is used (fail open) and a log is written |
| Trackpad list empty | Status line "Trackpad not found" (also when only non-trackpad devices are connected); retries on wake and device notifications |
| No Accessibility | The taps are not created; the engine runs. Since synthetic events sent without permission are not delivered, all edge actions other than the keyboard backlight, all corners, middle click and cursor freeze are off; the typing gate and the hold key also do not work. The diagram shows the effective (turned off) actions, the welcome cards say the permission is needed. "Grant Accessibility…" in the menu, a dot on the menu icon; on later launches the welcome window opens again |
| Tap was disabled by the system | Re-enabled inside the callback |
| DDC/Now Playing fails | Overlay "No DDC" / "No media"; log |
| Settings data corrupt | Defaults; log `error` |
| App exit during a slide | ⌘ is released, the taps are closed |

## 9. Test strategy

### 9.1 Engine unit tests (Swift Testing, in CI)

With a helper that produces synthetic `Frame`s (`FrameBuilder`); each rule is a test:

| # | Test | Rule |
|---|---|---|
| 1 | Movement starting outside the edge strip produces no command | 5.3 |
| 2 | Movement under 3 mm does not start a slide | slideStartMM |
| 3 | 60 mm up → 16 `stepVolume(+1)`, 16 `haptic(.step)` | stepMM |
| 4 | Down → −1 | direction |
| 5 | precision → `fine: true` | 5.5 |
| 6 | 4 mm perpendicular movement → spent, later frames are ignored | abortPerpendicularMM |
| 7 | A second finger cancels the slide, spent until it lifts | 5.4 |
| 8 | If the finger disappears and returns within 170 ms the slide continues; after 181 ms commit and freezeCursor(false) | lostTimeout |
| 9 | Watchdog `tick` → commit | 5.4 |
| 10 | Tap: 250 ms, 2 mm → no command | tap |
| 11 | Corner double tap within 350 ms → mute/screenshot; 351 ms → none | doubleTapWindow |
| 12 | Media edge double tap → mediaPlayPause; 20 mm slide → mediaNext | 5.5 |
| 13 | Three-finger tap → middleClick; none if not enabled; none if there is movement; works even if the fingers land in separate frames | threeFinger |
| 14 | majorAxis 21 mm → not a candidate; 19 mm → is | palm |
| 15 | No gesture starts within 400 ms of keyDown; a slide in progress continues | typingGate |
| 16 | holdKeyRequired && !satisfied → no gesture; release during sliding → commit | 5.6 |
| 17 | paused → everything is ignored, an active slide ends | 5.6 |
| 18 | bottomQuarterOnly → the left edge is not a candidate from y=0.5, it is from y=0.2 | 5.3 |
| 19 | Narrow/Wide strip width boundary | edgeWidthMM |
| 20 | When the left/right actions change (swap) the command type changes | 5.2 |
| 21 | switchApps: 24 mm → 2 `appSwitchStep(+1)`; commit on lift; second finger → cancel | 5.5 |
| 22 | scrubVideo: 12 mm → 2 `scrubStep(+1)`; scrubCommit on lift | 5.5 |
| 23 | `update(config:)` during sliding → commit and freezeCursor(false) | 5.8 |
| 24 | A frame from another device does not affect sliding | 5.4 |
| 25 | freezeCursor(true) once in each slide, (false) once at the end | 5.4 |
| 26 | A corner candidate starts a slide on the right/left edge with vertical movement | 5.4 |

### 9.2 TrrekProbe (local)

Subcommands: `devices` (list, surface size, built-in), `frames` (raw frame stream, exit with Ctrl-C), `layout-check`, `haptic <id>` (waveform), `key <name>` (media key event: volume-up, brightness-up, illumination-up, play…), `switcher` (⌘ held + Tab × 2 + release), `freeze <seconds>` (turns on Tap B and freezes the cursor), `mem` (prints its own RSS). Run in Phase 0 and after every macOS update.

### 9.3 Manual checklist

`docs/testing.md`: each edge and corner, middle click, precision, cursor freeze, typing gate, Hold/Toggle, pause in app, after sleep, the settings window and welcome look, plugging in an external trackpad (if available), a mouse with a touch surface (if available). Checked off in the PR template.

### 9.4 Resource measurement

`scripts/perf.sh`: starts the app, waits 30 s, prints the `footprint` and `ps -o %cpu,rss` output; threshold: RSS < 15 MB, CPU 0.0. The result is recorded in the README.

Note: memory is measured as the physical footprint (`phys_footprint`, `vmmap --summary`) instead of RSS; since RSS also counts shared system framework pages it does not show the app's own cost (decision 22). The threshold is a 15 MB footprint and 1% CPU. The measurement is started with `--skip-first-run` so that the welcome window does not spoil the measurement.

## 10. Git, CI/CD and development process

### 10.1 Branch model

- `main` always builds and is green. No direct commits; changes come by PR from `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, `test/` branches. Squash merge, the branch is deleted.
- Commit messages are English conventional commits; PR bodies are in Turkish.
- **Enforcement:** `scripts/install-hooks.sh` installs two local hooks: `pre-push` (rejects a direct push to `main`) and `pre-commit` (`swiftformat --lint` + `swiftlint`). A merge is made only with `gh pr merge --squash --delete-branch` and while CI is green. If the repository is made public or the plan is upgraded, the same rules are added as a ruleset (required check: `ci / build-test`).

### 10.2 PR life cycle (autonomous)

1. Open a branch, implement the task with TDD, `make check` must pass locally.
2. Push, `gh pr create` (per the template: summary, change type, test notes, manual checklist).
3. Wait for CI; if red, fix.
4. Independent review: a reviewer who has not seen the change (a separate context) reads the diff against the spec and CLAUDE.md; findings are fixed, the review summary is written to the PR as a comment ("Review: …", findings and result).
5. If `main` has advanced, `gh pr update-branch`, CI must be green again.
6. `gh pr merge --squash --delete-branch`; the CHANGELOG line must have come in the same PR.
7. Tags at milestones: `v0.1.0` (end of Phase 1), `v0.2.0` (end of Phase 2).

### 10.3 ci.yml

```yaml
on:
  pull_request: { paths-ignore: ['docs/**', '**/*.md'] }
  workflow_dispatch:
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  build-test:
    runs-on: macos-26
    timeout-minutes: 20
    steps: checkout → actions/cache (.build; key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift','Package.resolved') }})
           → swift build -c release --arch arm64 → swift test → swiftformat --lint . → swiftlint lint --strict
           → scripts/build-app.sh --version 0.0.0 --build ${{ github.run_number }} → zip dist/trrek.app → upload-artifact (7 days)
```

There is no push-to-main trigger (the content of a squash merge is the same as the PR head; the minute budget is preserved).

### 10.4 release.yml

`push: tags: ['v*.*.*']` → the same build and test → `scripts/build-app.sh --version ${TAG#v} --build ${{ github.run_number }}` → `ditto -c -k --keepParent dist/trrek.app trrek-${TAG}.zip` and a DMG with `hdiutil create` → `gh release create "$TAG" --generate-notes trrek-*.zip trrek-*.dmg` (`permissions: contents: write`).

### 10.5 Other

- `dependabot.yml`: `github-actions`, weekly.
- `PULL_REQUEST_TEMPLATE.md`: summary, change type, test notes, checklist (build, test, lint, `docs/testing.md`, perf impact, CHANGELOG).
- `Makefile`: `build`, `test`, `lint`, `format`, `app`, `install`, `check` (= the CI steps), `perf`, `probe`, `hooks`.
- `CHANGELOG.md`: version and date headings; each PR adds a line under "Unreleased".

## 11. Phases

**Phase 0 — Spike (TrrekProbe):** Results: [spike-results](2026-11-03-spike-results.md). The Platform work of Phase 1 does not start until these decisions are clear (the Engine work is independent):
1. The `MTTouch` layout and the surface size unit.
2. Whether a zero-touch frame arrives at lift-off (the watchdog stays anyway).
3. The haptic waveform IDs and the Light/Medium/Strong feel.
4. Whether the BRIGHTNESS and ILLUMINATION media key events show the HUD on macOS 27.2 (the 6.7 path choice).
5. Whether the quarter step with ⌥⇧ works.
6. The latency and effect of freezing the cursor with Tap B.
7. That holding ⌘ and sending Tab opens the switcher.
8. The idle memory of an empty LSUIElement app (budget verification).

**Phase 1 — Core:** Engine + 26 tests; Platform 6.1–6.7, 6.10; app 7.1–7.8 (Scrub Video and External Monitor Brightness disabled in settings); CI/CD 10.x; README, CHANGELOG, license. Finish: success criteria 1–5, tag `v0.1.0`.

**Phase 2 — Completers:** 6.8 DDC, 6.9 Scrub Video, the welcome animation, overlay and diagram polish, manual verification with an external trackpad (if a device is found). Tag `v0.2.0`.

## 12. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A macOS update changes the private symbols | Feature loss | dlsym + `isAvailable`, `TrrekProbe layout-check`, no crash |
| The media key event does not show the HUD | The system HUD goal | Spike 4; if needed CoreBrightness/CoreDisplay + our own overlay |
| Haptic waveforms feel different | Feel | Spike 3; strength choice in settings |
| No branch protection in the private repository | Discipline | Local hooks; the public/plan option is open |
| macOS runner minutes | CI interruption | PR-only trigger, paths-ignore, cache, concurrency; if exceeded a self-hosted runner |
| DDC cannot be verified | Phase 2 may stay incomplete | Best effort; verified when an external display is found |
| SwiftUI windows strain the memory budget | Perf goal | Windows are released when closed; `make perf` measures with the windows closed |
