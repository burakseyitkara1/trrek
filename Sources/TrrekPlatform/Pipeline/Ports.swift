import CoreGraphics
import TrrekEngine

/// How strongly the trackpad actuator plays haptic feedback.
public enum HapticStrength: String, CaseIterable, Codable, Sendable {
    case off, light, medium, strong
}

/// Which level indicator the on-screen overlay shows.
public enum OverlayKind: Sendable {
    case keyboardBacklight, externalBrightness, scrub
}

// The ports below are what `CommandDispatcher` drives. Unless noted otherwise, every method is called
// synchronously on the multitouch frame thread, so implementations must be thread-safe and must not block.

/// Posts system media keys (volume, brightness, playback, mute).
public protocol MediaKeyPosting: Sendable {
    func post(_ key: MediaKey, fine: Bool)
}

/// Posts synthetic keyboard events.
public protocol KeyPosting: Sendable {
    func press(keyCode: CGKeyCode, flags: CGEventFlags)
    func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags)
    func modifierUp(_ keyCode: CGKeyCode)
}

/// Posts synthetic mouse events.
public protocol MousePosting: Sendable {
    func middleClick()
}

/// Plays trackpad haptic feedback.
public protocol HapticPerforming: Sendable {
    func perform(_ event: HapticEvent, strength: HapticStrength)
}

/// Holds the pointer in place while a slide runs.
public protocol CursorFreezing: Sendable {
    func setFreeze(_ on: Bool)
}

/// Adjusts the keyboard backlight.
public protocol KeyboardBacklightControlling: Sendable {
    var isAvailable: Bool { get }
    /// The current level in 0...1, or `nil` when it cannot be read.
    func level() -> Float?
    /// Moves the backlight one step in `direction` (+1 brighter, -1 dimmer) and returns the new level in
    /// 0...1, or `nil` when the level could not be changed.
    func step(_ direction: Int, fine: Bool) -> Float?
}

/// Shows a transient level indicator. Called on the frame thread; implementations hop to the main thread.
public protocol LevelOverlayPresenting: Sendable {
    func show(kind: OverlayKind, level: Float, label: String?)
}
