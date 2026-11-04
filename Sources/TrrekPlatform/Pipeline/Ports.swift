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

/// Plays trackpad haptic feedback on the surface the gesture ran on.
public protocol HapticPerforming: Sendable {
    /// `device` is the engine's device ID of the gesture the haptic belongs to (`GesturePipeline.deviceID(of:)`).
    func perform(_ event: HapticEvent, strength: HapticStrength, device: UInt64)
}

/// Plays haptic feedback on one surface: a trackpad's actuator, or the system's generic haptics.
public protocol HapticActuating: Sendable {
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

/// Reads a system level (output volume, built-in display brightness) before a step, so a step at the end of the
/// range can be skipped. Called on the frame thread once per step, never per frame.
public protocol LevelReading: Sendable {
    /// The level in 0...1, or `nil` when it is unknown (then the step runs as if no reader existed).
    func level() -> Float?
}

/// Shows a transient level indicator. Called on the frame thread, or on the dispatcher's display queue for external
/// brightness; implementations hop to the main thread without waiting.
public protocol LevelOverlayPresenting: Sendable {
    func show(kind: OverlayKind, level: Float, label: String?)
}

/// Adjusts the brightness of external displays over DDC/CI.
///
/// `isExternal` is called on the frame thread and must be cheap. `step` talks to the display and waits on the
/// bus, so the dispatcher calls it only on its own serial queue, never on the frame thread.
public protocol ExternalBrightnessControlling: Sendable {
    /// Whether `display` is an external display (one that DDC/CI may reach).
    func isExternal(display: CGDirectDisplayID) -> Bool
    /// Moves `display`'s brightness `direction` steps (positive brighter, negative dimmer) and returns the new
    /// level in 0...1, or `nil` when the display could not be read or written.
    func step(display: CGDirectDisplayID, direction: Int, fine: Bool) -> Float?
}

/// A view of the system Mission Control app.
public enum MissionControlView: Sendable, Equatable, CaseIterable {
    /// Every window on every desktop.
    case all
    /// The windows of the front app.
    case appWindows
    /// The windows moved aside to show the desktop.
    case desktop

    /// The launch arguments that make the system Mission Control app open this view.
    public var arguments: [String] {
        switch self {
        case .all: []
        case .appWindows: ["2"]
        case .desktop: ["1"]
        }
    }
}

/// Opens Mission Control views without depending on the user's keyboard shortcut settings. Called on the frame thread
/// for a corner double tap; implementations hop off it without waiting.
public protocol MissionControlOpening: Sendable {
    func open(_ view: MissionControlView)
}
