import TrrekEngine
import TrrekPlatform

/// The titles and SF Symbol names the settings and welcome windows show for each option. Titles are looked up in the
/// app bundle's `Localizable.strings`; the English source text is the key.
public enum SettingsLabels {
    /// Why trrek asks for Accessibility; shown wherever the permission is missing.
    public static var accessibilityNeeded: String {
        String(
            localized: "trrek needs Accessibility access to change volume, brightness and the other controls.",
            bundle: .main
        )
    }

    /// The caption under the External Monitor Brightness setting.
    public static var externalBrightnessCaption: String {
        String(
            localized: "Monitors that support DDC/CI; the brightness edge follows the screen with the pointer",
            bundle: .main
        )
    }

    /// The caption under External Monitor Brightness: what it does, or that this Mac lacks the DDC/CI bridge.
    public static func externalBrightnessCaption(available: Bool) -> String {
        available ? externalBrightnessCaption : String(localized: "Not available on this Mac", bundle: .main)
    }

    // The label functions below are flat, exhaustive mappings that read best as one switch each.

    // swiftlint:disable:next cyclomatic_complexity
    public static func title(for action: EdgeAction) -> String {
        switch action {
        case .volume: String(localized: "Volume", bundle: .main)
        case .brightness: String(localized: "Brightness", bundle: .main)
        case .keyboardBacklight: String(localized: "Keyboard Backlight", bundle: .main)
        case .switchApps: String(localized: "Switch Apps", bundle: .main)
        case .switchTabs: String(localized: "Switch Tabs", bundle: .main)
        case .switchDesktops: String(localized: "Switch Desktops", bundle: .main)
        case .scrubVideo: String(localized: "Scrub Video", bundle: .main)
        case .media: String(localized: "Media", bundle: .main)
        case .zoom: String(localized: "Zoom", bundle: .main)
        case .undoRedo: String(localized: "Undo & Redo", bundle: .main)
        case .off: String(localized: "Off", bundle: .main)
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
        case .off: String(localized: "Off", bundle: .main)
        case .mute: String(localized: "Mute", bundle: .main)
        case .screenshot: String(localized: "Screenshot", bundle: .main)
        case .playPause: String(localized: "Play/Pause", bundle: .main)
        case .missionControl: String(localized: "Mission Control", bundle: .main)
        case .appWindows: String(localized: "App Windows", bundle: .main)
        case .showDesktop: String(localized: "Show Desktop", bundle: .main)
        case .spotlight: String(localized: "Spotlight", bundle: .main)
        case .lockScreen: String(localized: "Lock Screen", bundle: .main)
        case .screenshotArea: String(localized: "Screenshot Area", bundle: .main)
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

    public static func title(for edge: Edge) -> String {
        switch edge {
        case .left: String(localized: "Left Edge", bundle: .main)
        case .right: String(localized: "Right Edge", bundle: .main)
        case .top: String(localized: "Top Edge", bundle: .main)
        case .bottom: String(localized: "Bottom Edge", bundle: .main)
        }
    }

    public static func title(for corner: Corner) -> String {
        switch corner {
        case .topLeft: String(localized: "Top Left", bundle: .main)
        case .topRight: String(localized: "Top Right", bundle: .main)
        case .bottomLeft: String(localized: "Bottom Left", bundle: .main)
        case .bottomRight: String(localized: "Bottom Right", bundle: .main)
        }
    }

    public static func title(for strength: HapticStrength) -> String {
        switch strength {
        case .off: String(localized: "Off", bundle: .main)
        case .light: String(localized: "Light", bundle: .main)
        case .medium: String(localized: "Medium", bundle: .main)
        case .strong: String(localized: "Strong", bundle: .main)
        }
    }

    public static func title(for width: EdgeWidth) -> String {
        switch width {
        case .narrow: String(localized: "Narrow", bundle: .main)
        case .standard: String(localized: "Standard", bundle: .main)
        case .wide: String(localized: "Wide", bundle: .main)
        }
    }

    public static func title(for sensitivity: SlideSensitivity) -> String {
        switch sensitivity {
        case .veryLow: String(localized: "Very Low", bundle: .main)
        case .low: String(localized: "Low", bundle: .main)
        case .standard: String(localized: "Standard", bundle: .main)
        case .high: String(localized: "High", bundle: .main)
        case .veryHigh: String(localized: "Very High", bundle: .main)
        }
    }

    public static func title(for key: HoldKey) -> String {
        switch key {
        case .none: String(localized: "None", bundle: .main)
        case .shift: String(localized: "Shift", bundle: .main)
        case .control: String(localized: "Control", bundle: .main)
        case .option: String(localized: "Option", bundle: .main)
        case .command: String(localized: "Command", bundle: .main)
        }
    }

    public static func title(for mode: HoldKeyMode) -> String {
        switch mode {
        case .hold: String(localized: "Hold", bundle: .main)
        case .toggle: String(localized: "Toggle", bundle: .main)
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
        case .scrubVideo: String(localized: "Uses ← and → in the front app", bundle: .main)
        case .switchTabs: String(localized: "Uses ⌃⇥ and ⌃⇧⇥ in the front app", bundle: .main)
        case .switchDesktops: String(localized: "Uses ⌃← and ⌃→", bundle: .main)
        case .zoom: String(localized: "Uses ⌘= and ⌘− in the front app", bundle: .main)
        case .undoRedo: String(localized: "Uses ⌘Z and ⇧⌘Z in the front app", bundle: .main)
        case .keyboardBacklight where !backlightAvailable: String(localized: "Not available on this Mac", bundle: .main)
        default: nil
        }
    }

    /// The action an edge's menu checks and the diagram shows: the keyboard backlight appears as media control,
    /// which is what runs while its bridge is unavailable.
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

    /// The edges while the app with `bundleID` is in front; `nil` for the All Apps edges.
    public init(settings: Settings, backlightAvailable: Bool, accessibilityTrusted: Bool, bundleID: String? = nil) {
        let config = ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: backlightAvailable,
            accessibilityTrusted: accessibilityTrusted,
            frontmostBundleID: bundleID
        )
        self.init(left: config.left, right: config.right, top: config.top, bottom: config.bottom)
    }
}
