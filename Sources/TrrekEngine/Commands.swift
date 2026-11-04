public enum HapticEvent: Sendable, Equatable, Hashable {
    case start, step, tap, limit
}

public enum GestureCommand: Sendable, Equatable, Hashable {
    case stepVolume(Int, fine: Bool)
    case stepBrightness(Int, fine: Bool)
    case stepKeyboardBacklight(Int, fine: Bool)
    case appSwitchStep(Int)
    case appSwitchCommit
    case appSwitchCancel
    case scrubStep(Int)
    case scrubCommit
    case scrubCancel
    /// Next (+1) or previous (-1) tab in the front app.
    case tabSwitchStep(Int)
    /// The desktop (Space) to the right (+1) or left (-1).
    case desktopSwitchStep(Int)
    /// Zoom in (+1) or out (-1) in the front app.
    case zoomStep(Int)
    /// Redo (+1) or undo (-1) in the front app.
    case undoRedoStep(Int)
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case mute
    case screenshot
    /// Interactive screenshot of a selected area.
    case screenshotArea
    case missionControl
    /// The windows of the front app (Mission Control's application view).
    case appWindows
    case showDesktop
    case spotlight
    case lockScreen
    case middleClick
    case haptic(HapticEvent)
    case freezeCursor(Bool)
}

public protocol CommandSink: AnyObject {
    func handle(_ command: GestureCommand, device: UInt64)
}
