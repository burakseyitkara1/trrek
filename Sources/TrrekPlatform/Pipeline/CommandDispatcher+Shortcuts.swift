import CoreGraphics
import TrrekEngine

/// Virtual key codes of the keys the dispatcher presses (positions on the ANSI layout).
enum KeyCode {
    static let command: CGKeyCode = 55
    static let tab: CGKeyCode = 48
    static let escape: CGKeyCode = 53
    static let five: CGKeyCode = 23
    static let four: CGKeyCode = 21
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let equal: CGKeyCode = 24
    static let minus: CGKeyCode = 27
    static let zKey: CGKeyCode = 6
    static let qKey: CGKeyCode = 12
    static let space: CGKeyCode = 49

    /// The flags a physical arrow key carries. The system's desktop shortcuts (Control-arrow) only match arrows that
    /// carry the function and keypad flags, as the built-in keyboard's arrow keys do.
    static let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
}

// MARK: - Shortcuts and Mission Control

extension CommandDispatcher {
    /// Presses the keyboard shortcut of a step or corner command. Steps: +1 is forward (next tab, the desktop to the
    /// right, zoom in, redo), -1 back.
    func pressShortcut(for command: GestureCommand, ownAppFrontmost: Bool) {
        if ownAppFrontmost, Self.goesToTheFrontApp(command) {
            // Like scrub: in trrek's own window these keys would move focus or undo edits instead of reaching an app.
            return
        }
        switch command {
        case let .tabSwitchStep(direction):
            keys.press(keyCode: KeyCode.tab, flags: direction > 0 ? .maskControl : [.maskControl, .maskShift])
        case let .desktopSwitchStep(direction):
            let key = direction > 0 ? KeyCode.rightArrow : KeyCode.leftArrow
            keys.press(keyCode: key, flags: KeyCode.arrowFlags.union(.maskControl))
        case let .zoomStep(direction):
            keys.press(keyCode: direction > 0 ? KeyCode.equal : KeyCode.minus, flags: .maskCommand)
        case let .undoRedoStep(direction):
            keys.press(keyCode: KeyCode.zKey, flags: direction > 0 ? [.maskCommand, .maskShift] : .maskCommand)
        case .screenshot:
            keys.press(keyCode: KeyCode.five, flags: [.maskCommand, .maskShift])
        case .screenshotArea:
            keys.press(keyCode: KeyCode.four, flags: [.maskCommand, .maskShift])
        case .spotlight:
            keys.press(keyCode: KeyCode.space, flags: .maskCommand)
        case .lockScreen:
            keys.press(keyCode: KeyCode.qKey, flags: [.maskControl, .maskCommand])
        default:
            assertionFailure("no shortcut for this command")
        }
    }

    /// Whether a shortcut acts on the front app (tab switch, zoom, undo/redo) rather than system-wide.
    static func goesToTheFrontApp(_ command: GestureCommand) -> Bool {
        switch command {
        case .tabSwitchStep, .zoomStep, .undoRedoStep: true
        default: false
        }
    }

    /// Opens the Mission Control view of a corner command; logs and does nothing without the port.
    func openMissionControl(for command: GestureCommand) {
        let view: MissionControlView = switch command {
        case .appWindows: .appWindows
        case .showDesktop: .desktop
        default: .all
        }
        guard let missionControl else {
            platformLogger.error("mission control requested without a port")
            return
        }
        missionControl.open(view)
    }
}
