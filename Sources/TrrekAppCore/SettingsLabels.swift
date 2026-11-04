import TrrekEngine
import TrrekPlatform

/// The English titles and SF Symbol names the settings and welcome windows show for each option.
public enum SettingsLabels {
    /// Why trrek asks for Accessibility; shown wherever the permission is missing.
    public static let accessibilityNeeded =
        "trrek needs Accessibility access to change volume, brightness and the other controls."

    /// The caption under the External Monitor Brightness setting.
    public static let externalBrightnessCaption =
        "Monitors that support DDC/CI; the brightness edge follows the screen with the pointer"

    /// The caption under External Monitor Brightness: what it does, or that this Mac lacks the DDC/CI bridge.
    public static func externalBrightnessCaption(available: Bool) -> String {
        available ? externalBrightnessCaption : "Not available on this Mac"
    }

    // The label functions below are flat, exhaustive mappings that read best as one switch each.

    // swiftlint:disable:next cyclomatic_complexity
    public static func title(for action: EdgeAction) -> String {
        switch action {
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .keyboardBacklight: "Keyboard Backlight"
        case .switchApps: "Switch Apps"
        case .switchTabs: "Switch Tabs"
        case .switchDesktops: "Switch Desktops"
        case .scrubVideo: "Scrub Video"
        case .media: "Media"
        case .zoom: "Zoom"
        case .undoRedo: "Undo & Redo"
        case .off: "Off"
        }
    }

    /// `nil` for `.off`, which shows text only.
    public static func symbol(for action: EdgeAction) -> String? { // swiftlint:disable:this cyclomatic_complexity
        switch action {
        case .volume: "speaker.wave.2"
        case .brightness: "sun.max"
        case .keyboardBacklight: "keyboard"
        case .switchApps: "rectangle.on.rectangle"
        case .switchTabs: "rectangle.topthird.inset.filled"
        case .switchDesktops: "rectangle.split.3x1"
        case .scrubVideo: "film"
        case .media: "play"
        case .zoom: "plus.magnifyingglass"
        case .undoRedo: "arrow.uturn.backward"
        case .off: nil
        }
    }

    public static func title(for action: CornerAction) -> String {
        switch action {
        case .off: "Off"
        case .mute: "Mute"
        case .screenshot: "Screenshot"
        case .playPause: "Play/Pause"
        case .missionControl: "Mission Control"
        case .appWindows: "App Windows"
        case .showDesktop: "Show Desktop"
        case .spotlight: "Spotlight"
        case .lockScreen: "Lock Screen"
        case .screenshotArea: "Screenshot Area"
        }
    }

    /// `nil` for `.off`, which shows text only.
    public static func symbol(for action: CornerAction) -> String? {
        switch action {
        case .off: nil
        case .mute: "speaker.slash"
        case .screenshot: "camera.viewfinder"
        case .playPause: "playpause"
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .showDesktop: "menubar.dock.rectangle"
        case .spotlight: "magnifyingglass"
        case .lockScreen: "lock"
        case .screenshotArea: "rectangle.dashed"
        }
    }

    /// The action a click on a corner badge moves to: the next one in the order the pickers list them, and after the
    /// last one Off again.
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

    public static func title(for sensitivity: SlideSensitivity) -> String {
        switch sensitivity {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .standard: "Standard"
        case .high: "High"
        case .veryHigh: "Very High"
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

/// The options offered for every edge, and which of them can be picked on this Mac.
public enum EdgeChoices {
    /// Every edge offers the same actions, in this order.
    public static let all: [EdgeAction] = EdgeAction.allCases

    /// Only the keyboard backlight can be unavailable: it needs its bridge.
    public static func isSelectable(_ action: EdgeAction, backlightAvailable: Bool) -> Bool {
        action != .keyboardBacklight || backlightAvailable
    }

    /// A note shown beside an option (why it cannot be picked, or what it does), or `nil` when there is none.
    public static func caption(for action: EdgeAction, backlightAvailable: Bool) -> String? {
        switch action {
        case .scrubVideo: "Uses ← and → in the front app"
        case .switchTabs: "Uses ⌃⇥ and ⌃⇧⇥ in the front app"
        case .switchDesktops: "Uses ⌃← and ⌃→"
        case .zoom: "Uses ⌘= and ⌘− in the front app"
        case .undoRedo: "Uses ⌘Z and ⇧⌘Z in the front app"
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

/// The action each edge of the trackpad diagram shows: what the engine actually runs for these settings, including
/// the actions turned off while Accessibility is missing.
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

    public init(settings: Settings, backlightAvailable: Bool, accessibilityTrusted: Bool) {
        let config = ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: backlightAvailable,
            accessibilityTrusted: accessibilityTrusted
        )
        self.init(left: config.left, right: config.right, top: config.top, bottom: config.bottom)
    }
}
