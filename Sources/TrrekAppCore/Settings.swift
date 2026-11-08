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

/// How far a finger slides for each step. Lower sensitivity needs a longer slide per step.
public enum SlideSensitivity: String, CaseIterable, Codable, Sendable {
    case veryLow, low, standard, high, veryHigh

    /// The factor every step distance is multiplied by.
    public var multiplier: Float {
        switch self {
        case .veryLow: 1.6
        case .low: 1.25
        case .standard: 1.0
        case .high: 0.8
        case .veryHigh: 0.6
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
    public var slideSensitivity: SlideSensitivity = .standard
    public var externalMonitorBrightness = false
    // An edge set to the keyboard backlight runs media control while the backlight bridge is unavailable
    // (see `ConfigMapper`).
    public var leftEdge: EdgeAction = .brightness
    public var rightEdge: EdgeAction = .volume
    public var topEdge: EdgeAction = .switchApps
    public var bottomEdge: EdgeAction = .keyboardBacklight
    public var topLeft: CornerAction = .off
    public var topRight: CornerAction = .off
    public var bottomLeft: CornerAction = .off
    public var bottomRight: CornerAction = .off
    public var middleClick = false
    public var holdKey: HoldKey = .none
    public var holdKeyMode: HoldKeyMode = .hold
    public var pausedBundleIDs: [String] = []
    /// Apps whose edges differ from the ones above while they are in front (see `edgeActions(for:)`); at most
    /// `maximumEdgeProfiles`, never trrek itself, one per bundle ID.
    public var appEdgeProfiles: [AppEdgeProfile] = []
    public var launchAtLogin = true
    public var welcomeShown = false
    /// The interface language; it takes effect at the next launch (see `LanguagePreference`).
    public var language: AppLanguage = .system
    /// Whether trrek looks for a newer version by itself (at most once a day); Check Now works either way.
    public var checkForUpdatesAutomatically = true

    public init() {}
}

extension Settings {
    /// Fields earlier versions wrote that are only read now, to carry their meaning over.
    private enum LegacyKeys: String, CodingKey {
        /// Volume on the left edge and brightness on the right; replaced by `leftEdge` and `rightEdge`.
        case swapSides
    }

    /// Decodes forgivingly: a missing field, or one whose value cannot be read (such as an enum case this build
    /// does not know), takes its default while the other fields keep their stored values. Older schema versions
    /// load this way and become the current version. Only a blob written by a newer schema loads as all defaults,
    /// since its fields may mean something else.
    ///
    /// Settings from before per-edge side actions stored `swapSides`; when `leftEdge` and `rightEdge` are missing,
    /// `swapSides: true` loads as volume on the left and brightness on the right. `swapSides` is never written.
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
        slideSensitivity = Self.field(container, .slideSensitivity) ?? slideSensitivity
        externalMonitorBrightness = Self.field(container, .externalMonitorBrightness) ?? externalMonitorBrightness
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        if (try? legacy?.decodeIfPresent(Bool.self, forKey: .swapSides)) == true {
            leftEdge = .volume
            rightEdge = .brightness
        }
        leftEdge = Self.field(container, .leftEdge) ?? leftEdge
        rightEdge = Self.field(container, .rightEdge) ?? rightEdge
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
        // Each profile is read on its own: one that cannot be read is dropped and the others are kept.
        let profiles: [ForgivingElement<AppEdgeProfile>]? = Self.field(container, .appEdgeProfiles)
        appEdgeProfiles = Self.sanitized(profiles?.compactMap(\.value) ?? [])
        launchAtLogin = Self.field(container, .launchAtLogin) ?? launchAtLogin
        welcomeShown = Self.field(container, .welcomeShown) ?? welcomeShown
        language = Self.field(container, .language) ?? language
        checkForUpdatesAutomatically = Self.field(container, .checkForUpdatesAutomatically)
            ?? checkForUpdatesAutomatically
    }

    /// The stored value of `key`, or `nil` when it is missing or unreadable.
    private static func field<T: Decodable>(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> T? {
        guard let value = try? container.decodeIfPresent(T.self, forKey: key) else { return nil }
        return value
    }
}

public extension Settings {
    /// The action of one edge.
    subscript(edge edge: Edge) -> EdgeAction {
        get {
            switch edge {
            case .left: leftEdge
            case .right: rightEdge
            case .top: topEdge
            case .bottom: bottomEdge
            }
        }
        set {
            switch edge {
            case .left: leftEdge = newValue
            case .right: rightEdge = newValue
            case .top: topEdge = newValue
            case .bottom: bottomEdge = newValue
            }
        }
    }

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

    /// The defaults, keeping `launchAtLogin`, `welcomeShown` and `language`; every app's own edges are removed. Without
    /// the keyboard backlight bridge the bottom edge starts on media control.
    func resetToDefaults(backlightAvailable: Bool) -> Settings {
        var reset = Settings()
        reset.launchAtLogin = launchAtLogin
        reset.welcomeShown = welcomeShown
        reset.language = language
        if !backlightAvailable {
            reset.bottomEdge = .media
        }
        return reset
    }
}
