import TrrekEngine
import TrrekPlatform

/// The English titles and SF Symbol names the settings and welcome windows show for each option.
public enum SettingsLabels {
    public static func title(for action: EdgeAction) -> String {
        switch action {
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .switchApps: "Switch Apps"
        case .scrubVideo: "Scrub Video"
        case .keyboardBacklight: "Keyboard Backlight"
        case .media: "Media"
        case .off: "Off"
        }
    }

    /// `nil` for `.off`, which shows text only.
    public static func symbol(for action: EdgeAction) -> String? {
        switch action {
        case .volume: "speaker.wave.2"
        case .brightness: "sun.max"
        case .switchApps: "rectangle.on.rectangle"
        case .scrubVideo: "film"
        case .keyboardBacklight: "keyboard"
        case .media: "play"
        case .off: nil
        }
    }

    public static func title(for action: CornerAction) -> String {
        switch action {
        case .off: "Off"
        case .mute: "Mute"
        case .screenshot: "Screenshot"
        }
    }

    /// `nil` for `.off`, which shows text only.
    public static func symbol(for action: CornerAction) -> String? {
        switch action {
        case .off: nil
        case .mute: "speaker.slash"
        case .screenshot: "camera.viewfinder"
        }
    }

    /// The action a click on a corner badge moves to: Off, Mute, Screenshot, then Off again.
    public static func next(after action: CornerAction) -> CornerAction {
        let all = CornerAction.allCases
        let index = all.firstIndex(of: action) ?? all.startIndex
        let following = all.index(after: index)
        return following == all.endIndex ? all[all.startIndex] : all[following]
    }

    public static func title(for corner: Corner) -> String {
        switch corner {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    public static func title(for strength: HapticStrength) -> String {
        switch strength {
        case .off: "Off"
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    public static func title(for width: EdgeWidth) -> String {
        switch width {
        case .narrow: "Narrow"
        case .standard: "Standard"
        case .wide: "Wide"
        }
    }

    public static func title(for key: HoldKey) -> String {
        switch key {
        case .none: "None"
        case .shift: "Shift"
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        }
    }

    public static func title(for mode: HoldKeyMode) -> String {
        switch mode {
        case .hold: "Hold"
        case .toggle: "Toggle"
        }
    }
}

/// The options offered for the top and bottom edges, and which of them can be picked on this Mac.
public enum EdgeChoices {
    public static let topAndBottom: [EdgeAction] = [.switchApps, .scrubVideo, .keyboardBacklight, .media, .off]

    /// Video scrubbing is not available yet; the keyboard backlight needs its bridge.
    public static func isSelectable(_ action: EdgeAction, backlightAvailable: Bool) -> Bool {
        caption(for: action, backlightAvailable: backlightAvailable) == nil
    }

    /// Why an option cannot be picked, or `nil` when it can.
    public static func caption(for action: EdgeAction, backlightAvailable: Bool) -> String? {
        switch action {
        case .scrubVideo: "Coming later"
        case .keyboardBacklight where !backlightAvailable: "Not available on this Mac"
        default: nil
        }
    }

    /// The option a picker shows: the keyboard backlight appears as media control, which is what runs while its
    /// bridge is unavailable.
    public static func displayed(_ action: EdgeAction, backlightAvailable: Bool) -> EdgeAction {
        action == .keyboardBacklight && !backlightAvailable ? .media : action
    }
}

/// The action each edge of the trackpad diagram shows: what the engine actually runs for these settings.
public struct DiagramEdges: Equatable, Sendable {
    public var left: EdgeAction
    public var right: EdgeAction
    public var top: EdgeAction
    public var bottom: EdgeAction

    public init(left: EdgeAction, right: EdgeAction, top: EdgeAction, bottom: EdgeAction) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    /// Accessibility is assumed granted: the diagram shows the configured layout, not the gated one.
    public init(settings: Settings, backlightAvailable: Bool) {
        let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: backlightAvailable)
        self.init(left: config.left, right: config.right, top: config.top, bottom: config.bottom)
    }
}
