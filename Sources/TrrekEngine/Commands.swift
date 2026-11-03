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
    case mediaPlayPause
    case mediaNext
    case mediaPrevious
    case mute
    case screenshot
    case middleClick
    case haptic(HapticEvent)
    case freezeCursor(Bool)
}

public protocol CommandSink: AnyObject {
    func handle(_ command: GestureCommand, device: UInt64)
}
