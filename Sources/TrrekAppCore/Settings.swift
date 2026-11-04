import os
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

extension Settings {
    /// Decodes forgivingly: a missing field, or one whose value cannot be read (such as an enum case this build
    /// does not know), takes its default while the other fields keep their stored values. Older schema versions
    /// load this way and become the current version. Only a blob written by a newer schema loads as all defaults,
    /// since its fields may mean something else.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = Self.field(container, .schemaVersion) ?? Settings.currentSchemaVersion
        guard stored <= Settings.currentSchemaVersion else {
            appLogger.error("settings schema \(stored, privacy: .public) is newer than this build, using defaults")
            return
        }
        hapticStrength = Self.field(container, .hapticStrength) ?? hapticStrength
        edgeWidth = Self.field(container, .edgeWidth) ?? edgeWidth
        precision = Self.field(container, .precision) ?? precision
        freezeCursor = Self.field(container, .freezeCursor) ?? freezeCursor
        bottomQuarterOnly = Self.field(container, .bottomQuarterOnly) ?? bottomQuarterOnly
        swapSides = Self.field(container, .swapSides) ?? swapSides
        externalMonitorBrightness = Self.field(container, .externalMonitorBrightness) ?? externalMonitorBrightness
        topEdge = Self.field(container, .topEdge) ?? topEdge
        bottomEdge = Self.field(container, .bottomEdge) ?? bottomEdge
        topLeft = Self.field(container, .topLeft) ?? topLeft
        topRight = Self.field(container, .topRight) ?? topRight
        bottomLeft = Self.field(container, .bottomLeft) ?? bottomLeft
        bottomRight = Self.field(container, .bottomRight) ?? bottomRight
        middleClick = Self.field(container, .middleClick) ?? middleClick
        holdKey = Self.field(container, .holdKey) ?? holdKey
        holdKeyMode = Self.field(container, .holdKeyMode) ?? holdKeyMode
        pausedBundleIDs = Self.field(container, .pausedBundleIDs) ?? pausedBundleIDs
        launchAtLogin = Self.field(container, .launchAtLogin) ?? launchAtLogin
        welcomeShown = Self.field(container, .welcomeShown) ?? welcomeShown
    }

    /// The stored value of `key`, or `nil` when it is missing or unreadable.
    private static func field<T: Decodable>(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> T? {
        guard let value = try? container.decodeIfPresent(T.self, forKey: key) else { return nil }
        return value
    }
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
