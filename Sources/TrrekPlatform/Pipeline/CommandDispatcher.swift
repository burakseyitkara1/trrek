import CoreGraphics
import Synchronization
import TrrekEngine

/// Carries out engine commands through the injected ports.
///
/// `handle`, `releaseAll()` and `hapticStrength` may be used from any thread. Every call, including the port
/// calls it makes, runs under one mutex, so a `releaseAll()` can never interleave with a command half-way
/// (for example posting Command-up between a switcher's Command-down and its Tab). Ports must therefore never
/// call back into the dispatcher.
public final class CommandDispatcher: CommandSink, @unchecked Sendable {
    private enum KeyCode {
        static let command: CGKeyCode = 55
        static let tab: CGKeyCode = 48
        static let escape: CGKeyCode = 53
        static let five: CGKeyCode = 23
    }

    private struct State {
        var hapticStrength: HapticStrength = .medium
        /// Command is held down for the app switcher.
        var switcherHeld = false
    }

    private let mediaKeys: any MediaKeyPosting
    private let keys: any KeyPosting
    private let mouse: any MousePosting
    private let haptics: any HapticPerforming
    private let freezer: any CursorFreezing
    private let backlight: (any KeyboardBacklightControlling)?
    private let overlay: (any LevelOverlayPresenting)?
    private let state = Mutex(State())

    public init(
        mediaKeys: any MediaKeyPosting,
        keys: any KeyPosting,
        mouse: any MousePosting,
        haptics: any HapticPerforming,
        freezer: any CursorFreezing,
        backlight: (any KeyboardBacklightControlling)?,
        overlay: (any LevelOverlayPresenting)?
    ) {
        self.mediaKeys = mediaKeys
        self.keys = keys
        self.mouse = mouse
        self.haptics = haptics
        self.freezer = freezer
        self.backlight = backlight
        self.overlay = overlay
    }

    public var hapticStrength: HapticStrength {
        get { state.withLock { $0.hapticStrength } }
        set { state.withLock { $0.hapticStrength = newValue } }
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
        switch command {
        case let .stepVolume(direction, fine):
            mediaKeys.post(direction > 0 ? .soundUp : .soundDown, fine: fine)
        case let .stepBrightness(direction, fine):
            mediaKeys.post(direction > 0 ? .brightnessUp : .brightnessDown, fine: fine)
        case let .stepKeyboardBacklight(direction, fine):
            stepBacklight(direction, fine: fine, hapticStrength: state.hapticStrength)
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
        case .scrubStep, .scrubCommit, .scrubCancel:
            platformLogger.info("scrub commands are not supported yet; ignored")
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
            if state.hapticStrength != .off {
                haptics.perform(event, strength: state.hapticStrength)
            }
        case let .freezeCursor(on):
            freezer.setFreeze(on)
        }
    }

    /// Steps the backlight and shows its level. A step that cannot move because the level already sits at 0 or 1
    /// plays the limit haptic, as the system levels do at their ends.
    private func stepBacklight(_ direction: Int, fine: Bool, hapticStrength: HapticStrength) {
        guard let backlight, backlight.isAvailable else { return }
        let previous = backlight.level()
        guard let level = backlight.step(direction, fine: fine) else { return }
        if level == previous, level == 0 || level == 1, hapticStrength != .off {
            haptics.perform(.limit, strength: hapticStrength)
        }
        overlay?.show(kind: .keyboardBacklight, level: level, label: nil)
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
