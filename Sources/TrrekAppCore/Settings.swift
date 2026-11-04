import TrrekEngine
import TrrekPlatform

/// How wide the edge strips are.
public enum EdgeWidth: String, CaseIterable, Codable, Sendable {
    case narrow, standard, wide

    /// Width of an edge strip in millimetres.
    public var millimetres: Float {
        switch self {
        case .narrow: 7
        case .standard: 10
        case .wide: 14
        }
    }
}

/// Everything the user can configure. Stored as JSON by `SettingsStore`.
public struct Settings: Codable, Equatable, Sendable {
    /// Bumped whenever the stored format changes incompatibly.
    public static let currentSchemaVersion = 1

    public var schemaVersion = Settings.currentSchemaVersion
    public var hapticStrength: HapticStrength = .medium
    public var edgeWidth: EdgeWidth = .standard
    public var precision = false
    public var freezeCursor = true
    public var bottomQuarterOnly = false
    public var swapSides = false
    public var externalMonitorBrightness = false
    public var topEdge: EdgeAction = .switchApps
    /// Falls back to `.media` while the keyboard backlight bridge is unavailable (see `ConfigMapper`).
    public var bottomEdge: EdgeAction = .keyboardBacklight
    public var topLeft: CornerAction = .off
    public var topRight: CornerAction = .off
    public var bottomLeft: CornerAction = .off
    public var bottomRight: CornerAction = .off
    public var middleClick = false
    public var holdKey: HoldKey = .none
    public var holdKeyMode: HoldKeyMode = .hold
    public var pausedBundleIDs: [String] = []
    public var launchAtLogin = true
    public var welcomeShown = false

    public init() {}
}

public extension Settings {
    /// The action of one corner.
    subscript(corner corner: Corner) -> CornerAction {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomLeft: bottomLeft
            case .bottomRight: bottomRight
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomLeft: bottomLeft = newValue
            case .bottomRight: bottomRight = newValue
            }
        }
    }

    /// The defaults, keeping `launchAtLogin` and `welcomeShown`. Without the keyboard backlight bridge the bottom
    /// edge starts on media control.
    func resetToDefaults(backlightAvailable: Bool) -> Settings {
        var reset = Settings()
        reset.launchAtLogin = launchAtLogin
        reset.welcomeShown = welcomeShown
        if !backlightAvailable {
            reset.bottomEdge = .media
        }
        return reset
    }
}
