import Foundation
import TrrekPlatform

/// Reads and writes `Settings` as JSON in user defaults.
///
/// Decoding is forgiving (see `Settings.init(from:)`): missing or unreadable fields take their defaults, and only
/// data that is not a settings object at all or was written by a newer schema version loads as all defaults. The
/// stored value is left alone until the next `save`.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: key) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            appLogger.error("settings unreadable, using defaults", error)
            return Settings()
        }
    }

    public func save(_ settings: Settings) {
        do {
            try defaults.set(JSONEncoder().encode(settings), forKey: key)
        } catch {
            appLogger.error("settings could not be saved", error)
        }
    }
}
