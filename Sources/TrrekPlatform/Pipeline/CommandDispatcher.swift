import CoreGraphics
import Dispatch
import Synchronization
import TrrekEngine

/// Carries out engine commands through the injected ports.
///
/// `handle`, `releaseAll()` and `hapticStrength` may be used from any thread. Every call, including the port
/// calls it makes, runs under one mutex, so a `releaseAll()` can never interleave with a command half-way
/// (for example posting Command-up between a switcher's Command-down and its Tab). Ports must therefore never
/// call back into the dispatcher.
///
/// External display brightness is the exception to running on the caller's thread: DDC/CI transfers wait on the
/// bus, so `handle` only decides on the frame thread whether the pointer's display is external and hands the step
/// to a serial queue, which talks to the display and updates the overlay. Steps that arrive while the queue is
/// busy are merged into one pending step per display and precision, so a fast slide neither lags nor overshoots.
///
/// Level limits: a level step (volume, brightness, keyboard backlight) reads the level first when it can. When the
/// level already sits at the bound the step pushes against, the step is skipped; the first such step of a slide
/// plays one limit haptic, later ones play nothing, and the step haptic the engine sends right after each is
/// dropped. Step haptics resume when the direction reverses or a new slide starts. An external display's level is
/// only known on the display queue, so its limit haptic plays there, at the first result at a bound.
public final class CommandDispatcher: CommandSink, @unchecked Sendable {
    /// A level a slide can run into the end of.
    private enum LevelKind: Equatable {
        case volume, brightness, keyboardBacklight
    }

    /// The bound a slide reached: the level and the direction that pushes against it.
    private struct Limit: Equatable {
        let kind: LevelKind
        let direction: Int
    }

    /// The last level read back from an external display, and the slide in which its limit haptic played.
    private struct DDCLevel {
        var level: Float
        var limitSlide: UInt64?
    }

    private struct State {
        var hapticStrength: HapticStrength = .medium
        /// Command is held down for the app switcher.
        var switcherHeld = false
        /// Net arrow-key steps of the current scrub slide.
        var scrubSteps = 0
        var externalBrightnessEnabled = false
        /// trrek itself is the frontmost application, so scrub has no player to send arrow keys to.
        var ownAppFrontmost = false
        /// The previous command was a level step skipped at a bound, so the step haptic the engine sends right after
        /// it is dropped.
        var dropStepHaptic = false
        /// The bound the current slide reached and played the limit haptic for; `nil` while it is not at one.
        var atLimit: Limit?
        /// Counts slides (each `.haptic(.start)`), so an external display's limit haptic plays once per slide.
        var slide: UInt64 = 0
        /// The last level each external display reported; read on the frame thread, written on the display queue.
        var ddcLevels: [CGDirectDisplayID: DDCLevel] = [:]
        /// The engine's device ID of the latest command, so haptics play on the trackpad the gesture runs on.
        var device: UInt64 = 0
    }

    private let mediaKeys: any MediaKeyPosting
    /// Internal so the shortcut presses in `CommandDispatcher+Shortcuts.swift` reach it.
    let keys: any KeyPosting
    private let mouse: any MousePosting
    private let haptics: any HapticPerforming
    private let freezer: any CursorFreezing
    private let backlight: (any KeyboardBacklightControlling)?
    private let overlay: (any LevelOverlayPresenting)?
    private let externalBrightness: (any ExternalBrightnessControlling)?
    private let volumeLevel: (any LevelReading)?
    private let brightnessLevel: (any LevelReading)?
    /// Internal so `CommandDispatcher+Shortcuts.swift` reaches it.
    let missionControl: (any MissionControlOpening)?
    private let displayLocator: @Sendable () -> CGDirectDisplayID?
    /// Where DDC/CI steps run, in order, off the frame thread.
    private let displayQueue: DispatchQueue
    private let state = Mutex(State())
    /// DDC steps waiting for the display queue, oldest first; each has exactly one queued block that takes it.
    private let pendingSteps = Mutex(PendingSteps())

    /// A merged DDC step: `steps` is the net step count for `display` at one precision.
    private struct PendingStep {
        let display: CGDirectDisplayID
        let fine: Bool
        var steps: Int
    }

    private struct PendingSteps {
        var queue: [PendingStep] = []

        init() {
            queue.reserveCapacity(4)
        }
    }

    public init(
        mediaKeys: any MediaKeyPosting,
        keys: any KeyPosting,
        mouse: any MousePosting,
        haptics: any HapticPerforming,
        freezer: any CursorFreezing,
        backlight: (any KeyboardBacklightControlling)?,
        overlay: (any LevelOverlayPresenting)?,
        externalBrightness: (any ExternalBrightnessControlling)? = nil,
        displayLocator: @escaping @Sendable () -> CGDirectDisplayID? = { nil },
        volumeLevel: (any LevelReading)? = nil,
        brightnessLevel: (any LevelReading)? = nil,
        missionControl: (any MissionControlOpening)? = nil,
        displayQueue: DispatchQueue = DispatchQueue(label: "com.burakseyitkara.trrek.ddc", qos: .userInitiated)
    ) {
        self.mediaKeys = mediaKeys
        self.keys = keys
        self.mouse = mouse
        self.haptics = haptics
        self.freezer = freezer
        self.backlight = backlight
        self.overlay = overlay
        self.externalBrightness = externalBrightness
        self.displayLocator = displayLocator
        self.volumeLevel = volumeLevel
        self.brightnessLevel = brightnessLevel
        self.missionControl = missionControl
        self.displayQueue = displayQueue
    }

    public var hapticStrength: HapticStrength {
        get { state.withLock { $0.hapticStrength } }
        set { state.withLock { $0.hapticStrength = newValue } }
    }

    /// Whether brightness steps go to an external display under the pointer over DDC/CI.
    public var externalBrightnessEnabled: Bool {
        get { state.withLock { $0.externalBrightnessEnabled } }
        set { state.withLock { $0.externalBrightnessEnabled = newValue } }
    }

    /// Whether trrek itself is frontmost. Scrub, tab switch, zoom and undo/redo steps are dropped meanwhile: their keys
    /// would move the selection or focus in trrek's own window (a picker, the paused apps list) instead of reaching
    /// another app. Desktop switching is system-wide and still runs.
    public var ownAppFrontmost: Bool {
        get { state.withLock { $0.ownAppFrontmost } }
        set { state.withLock { $0.ownAppFrontmost = newValue } }
    }

    public func handle(_ command: GestureCommand, device: UInt64) {
        state.withLock { state in
            state.device = device
            apply(command, &state)
        }
    }

    /// Releases anything trrek holds down: the Command key of the app switcher and the cursor freeze.
    public func releaseAll() {
        state.withLock { state in
            if state.switcherHeld {
                keys.modifierUp(KeyCode.command)
                state.switcherHeld = false
            }
            freezer.setFreeze(false)
        }
    }

    // A flat, exhaustive command-to-port mapping reads best as one switch.
    // swiftlint:disable:next cyclomatic_complexity
    private func apply(_ command: GestureCommand, _ state: inout State) {
        let dropStepHaptic = state.dropStepHaptic
        state.dropStepHaptic = false
        switch command {
        case let .stepVolume(direction, fine):
            if !skipAtLimit(.volume, direction, level: volumeLevel?.level(), &state) {
                mediaKeys.post(direction > 0 ? .soundUp : .soundDown, fine: fine)
            }
        case let .stepBrightness(direction, fine):
            stepBrightness(direction, fine: fine, &state)
        case let .stepKeyboardBacklight(direction, fine):
            stepBacklight(direction, fine: fine, &state)
        case let .appSwitchStep(direction):
            if !state.switcherHeld {
                keys.modifierDown(KeyCode.command, flags: .maskCommand)
                state.switcherHeld = true
            }
            keys.press(keyCode: KeyCode.tab, flags: direction > 0 ? .maskCommand : [.maskCommand, .maskShift])
        case .appSwitchCommit:
            switcherEnd(cancel: false, &state)
        case .appSwitchCancel:
            switcherEnd(cancel: true, &state)
        case let .scrubStep(direction):
            guard !state.ownAppFrontmost else { break }
            keys.press(keyCode: direction > 0 ? KeyCode.rightArrow : KeyCode.leftArrow, flags: [])
            state.scrubSteps += direction > 0 ? 1 : -1
            overlay?.show(kind: .scrub, level: 0.5, label: ScrubLabel.text(steps: state.scrubSteps))
        case .scrubCommit, .scrubCancel:
            state.atLimit = nil
            state.scrubSteps = 0
        case .tabSwitchStep, .zoomStep, .undoRedoStep, .desktopSwitchStep, .screenshot, .screenshotArea, .spotlight,
             .lockScreen:
            pressShortcut(for: command, ownAppFrontmost: state.ownAppFrontmost)
        case .missionControl, .appWindows, .showDesktop:
            openMissionControl(for: command)
        case .mediaPlayPause:
            mediaKeys.post(.play, fine: false)
        case .mediaNext:
            mediaKeys.post(.next, fine: false)
        case .mediaPrevious:
            mediaKeys.post(.previous, fine: false)
        case .mute:
            mediaKeys.post(.mute, fine: false)
        case .middleClick:
            mouse.middleClick()
        case let .haptic(event):
            haptic(event, dropStep: dropStepHaptic, &state)
        case let .freezeCursor(on):
            state.atLimit = on ? state.atLimit : nil
            freezer.setFreeze(on)
        }
    }

    /// Plays an engine haptic. `.start` begins a new slide, which ends any limit; a step haptic is dropped when the
    /// step before it was skipped at a limit.
    private func haptic(_ event: HapticEvent, dropStep: Bool, _ state: inout State) {
        if event == .start {
            state.atLimit = nil
            state.slide &+= 1
        }
        if state.hapticStrength != .off, !(event == .step && dropStep) {
            haptics.perform(event, strength: state.hapticStrength, device: state.device)
        }
    }

    /// Whether a step is skipped because `level` already sits at the bound `direction` pushes against. The first
    /// such step in a row plays the limit haptic; every one drops the step haptic that follows it. Any other step
    /// (an unknown level, or one that can move) ends the limit, so reversing the direction plays step haptics again.
    private func skipAtLimit(_ kind: LevelKind, _ direction: Int, level: Float?, _ state: inout State) -> Bool {
        guard let level, LevelBounds.isAtBound(level, direction: direction) else {
            state.atLimit = nil
            return false
        }
        let limit = Limit(kind: kind, direction: direction)
        if state.atLimit != limit {
            state.atLimit = limit
            playLimit(state)
        }
        state.dropStepHaptic = true
        return true
    }

    private func playLimit(_ state: State) {
        if state.hapticStrength != .off {
            haptics.perform(.limit, strength: state.hapticStrength, device: state.device)
        }
    }

    /// Steps the backlight and shows its level; at a bound it shows the level without stepping.
    private func stepBacklight(_ direction: Int, fine: Bool, _ state: inout State) {
        guard let backlight, backlight.isAvailable else { return }
        let current = backlight.level()
        if skipAtLimit(.keyboardBacklight, direction, level: current, &state) {
            overlay?.show(kind: .keyboardBacklight, level: current ?? 0, label: nil)
            return
        }
        guard let level = backlight.step(direction, fine: fine) else { return }
        overlay?.show(kind: .keyboardBacklight, level: level, label: nil)
    }

    /// Steps the external display under the pointer over DDC/CI when that is enabled, otherwise posts the
    /// brightness media key (the built-in display, or DDC turned off). The DDC step runs on `displayQueue`; the
    /// overlay shows the new level, or "No DDC" when the display could not be reached.
    private func stepBrightness(_ direction: Int, fine: Bool, _ state: inout State) {
        guard state.externalBrightnessEnabled, let externalBrightness, let display = displayLocator(),
              externalBrightness.isExternal(display: display)
        else {
            if !skipAtLimit(.brightness, direction, level: brightnessLevel?.level(), &state) {
                mediaKeys.post(direction > 0 ? .brightnessUp : .brightnessDown, fine: fine)
            }
            return
        }
        state.atLimit = nil
        // The display was already at this bound: its step haptic is dropped. The step still goes to the display,
        // which may have been changed with its own buttons since.
        if let known = state.ddcLevels[display], LevelBounds.isAtBound(known.level, direction: direction) {
            state.dropStepHaptic = true
        }
        // Joins the newest pending step when it is for the same display and precision (its block has not run
        // yet); otherwise adds a step and queues the one block that will take it.
        let schedule = pendingSteps.withLock { pending in
            if let last = pending.queue.last, last.display == display, last.fine == fine {
                pending.queue[pending.queue.count - 1].steps += direction
                return false
            }
            pending.queue.append(PendingStep(display: display, fine: fine, steps: direction))
            return true
        }
        guard schedule else { return }
        displayQueue.async { [self] in
            let step = pendingSteps.withLock { $0.queue.removeFirst() }
            let level = externalBrightness.step(display: step.display, direction: step.steps, fine: step.fine)
            if let level {
                self.state.withLock { recordDDCLevel(level, display: step.display, steps: step.steps, &$0) }
            }
            overlay?.show(kind: .externalBrightness, level: level ?? 0, label: level == nil ? "No DDC" : nil)
        }
    }

    /// Remembers an external display's new level. The first result at the bound the steps pushed against plays the
    /// limit haptic, once per slide; a level away from the bound lets it play again.
    private func recordDDCLevel(_ level: Float, display: CGDirectDisplayID, steps: Int, _ state: inout State) {
        var entry = state.ddcLevels[display] ?? DDCLevel(level: level, limitSlide: nil)
        entry.level = level
        if LevelBounds.isAtBound(level, direction: steps) {
            if entry.limitSlide != state.slide {
                entry.limitSlide = state.slide
                playLimit(state)
            }
        } else {
            entry.limitSlide = nil
        }
        state.ddcLevels[display] = entry
    }

    private func switcherEnd(cancel: Bool, _ state: inout State) {
        state.atLimit = nil
        guard state.switcherHeld else { return }
        state.switcherHeld = false
        if cancel {
            keys.press(keyCode: KeyCode.escape, flags: .maskCommand)
        }
        keys.modifierUp(KeyCode.command)
    }
}

/// The scrub overlay's text. It lives in the platform layer because the dispatcher builds it; `OverlayContent`
/// re-exposes it for the app layer.
public enum ScrubLabel {
    /// The net scrub distance as signed seconds ("+15 s", "\u{2212}10 s", "0 s"), assuming 5 s per step.
    public static func text(steps: Int) -> String {
        let seconds = steps * 5
        guard seconds != 0 else {
            return "0 s"
        }
        return seconds > 0 ? "+\(seconds) s" : "\u{2212}\(-seconds) s"
    }
}
