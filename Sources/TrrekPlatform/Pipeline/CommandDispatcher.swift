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
public final class CommandDispatcher: CommandSink, @unchecked Sendable {
    private enum KeyCode {
        static let command: CGKeyCode = 55
        static let tab: CGKeyCode = 48
        static let escape: CGKeyCode = 53
        static let five: CGKeyCode = 23
        static let leftArrow: CGKeyCode = 123
        static let rightArrow: CGKeyCode = 124
    }

    private struct State {
        var hapticStrength: HapticStrength = .medium
        /// Command is held down for the app switcher.
        var switcherHeld = false
        /// Net arrow-key steps of the current scrub slide.
        var scrubSteps = 0
        var externalBrightnessEnabled = false
        /// The previous command was a backlight step that hit a bound and played the limit haptic, so the step
        /// haptic the engine sends right after it is dropped.
        var backlightAtLimit = false
    }

    private let mediaKeys: any MediaKeyPosting
    private let keys: any KeyPosting
    private let mouse: any MousePosting
    private let haptics: any HapticPerforming
    private let freezer: any CursorFreezing
    private let backlight: (any KeyboardBacklightControlling)?
    private let overlay: (any LevelOverlayPresenting)?
    private let externalBrightness: (any ExternalBrightnessControlling)?
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

    public func handle(_ command: GestureCommand, device _: UInt64) {
        state.withLock { apply(command, &$0) }
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
        let backlightAtLimit = state.backlightAtLimit
        state.backlightAtLimit = false
        switch command {
        case let .stepVolume(direction, fine):
            mediaKeys.post(direction > 0 ? .soundUp : .soundDown, fine: fine)
        case let .stepBrightness(direction, fine):
            stepBrightness(direction, fine: fine, externalEnabled: state.externalBrightnessEnabled)
        case let .stepKeyboardBacklight(direction, fine):
            state.backlightAtLimit = stepBacklight(direction, fine: fine, hapticStrength: state.hapticStrength)
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
            keys.press(keyCode: direction > 0 ? KeyCode.rightArrow : KeyCode.leftArrow, flags: [])
            state.scrubSteps += direction > 0 ? 1 : -1
            overlay?.show(kind: .scrub, level: 0.5, label: ScrubLabel.text(steps: state.scrubSteps))
        case .scrubCommit, .scrubCancel:
            state.scrubSteps = 0
        case .mediaPlayPause:
            mediaKeys.post(.play, fine: false)
        case .mediaNext:
            mediaKeys.post(.next, fine: false)
        case .mediaPrevious:
            mediaKeys.post(.previous, fine: false)
        case .mute:
            mediaKeys.post(.mute, fine: false)
        case .screenshot:
            keys.press(keyCode: KeyCode.five, flags: [.maskCommand, .maskShift])
        case .middleClick:
            mouse.middleClick()
        case let .haptic(event):
            if state.hapticStrength != .off, !(event == .step && backlightAtLimit) {
                haptics.perform(event, strength: state.hapticStrength)
            }
        case let .freezeCursor(on):
            freezer.setFreeze(on)
        }
    }

    /// Steps the backlight and shows its level. A step that cannot move because the level already sits at 0 or 1
    /// plays the limit haptic, as the system levels do at their ends. Returns whether the step hit a bound.
    private func stepBacklight(_ direction: Int, fine: Bool, hapticStrength: HapticStrength) -> Bool {
        guard let backlight, backlight.isAvailable else { return false }
        let previous = backlight.level()
        guard let level = backlight.step(direction, fine: fine) else { return false }
        let atLimit = level == previous && (level == 0 || level == 1)
        if atLimit, hapticStrength != .off {
            haptics.perform(.limit, strength: hapticStrength)
        }
        overlay?.show(kind: .keyboardBacklight, level: level, label: nil)
        return atLimit
    }

    /// Steps the external display under the pointer over DDC/CI when that is enabled, otherwise posts the
    /// brightness media key (the built-in display, or DDC turned off). The DDC step runs on `displayQueue`; the
    /// overlay shows the new level, or "No DDC" when the display could not be reached.
    private func stepBrightness(_ direction: Int, fine: Bool, externalEnabled: Bool) {
        guard externalEnabled, let externalBrightness, let display = displayLocator(),
              externalBrightness.isExternal(display: display)
        else {
            mediaKeys.post(direction > 0 ? .brightnessUp : .brightnessDown, fine: fine)
            return
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
            overlay?.show(kind: .externalBrightness, level: level ?? 0, label: level == nil ? "No DDC" : nil)
        }
    }

    private func switcherEnd(cancel: Bool, _ state: inout State) {
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
