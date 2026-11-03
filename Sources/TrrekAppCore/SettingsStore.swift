import Foundation

/// Reads and writes `Settings` as JSON in user defaults.
///
/// Unreadable data or data written with another schema version loads as the defaults; the stored value is
/// left alone until the next `save`.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: key) else { return Settings() }
        let settings: Settings
        do {
            settings = try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            appLogger.error("settings unreadable, using defaults: \(String(describing: error), privacy: .public)")
            return Settings()
        }
        guard settings.schemaVersion == Settings.currentSchemaVersion else {
            appLogger.error("settings schema \(settings.schemaVersion, privacy: .public) unsupported, using defaults")
            return Settings()
        }
        return settings
    }

    public func save(_ settings: Settings) {
        do {
            try defaults.set(JSONEncoder().encode(settings), forKey: key)
        } catch {
            appLogger.error("settings could not be saved: \(String(describing: error), privacy: .public)")
        }
    }
}
