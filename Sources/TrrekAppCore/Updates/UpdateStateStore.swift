import Foundation

/// What the update check remembers between launches, in the app's user defaults beside (not inside) the settings,
/// so it is never exported to a `.trrek` file.
public final class UpdateStateStore: @unchecked Sendable {
    private enum Key {
        static let lastCheck = "lastUpdateCheck"
        static let lastFailure = "lastFailedUpdateCheck"
        static let availableUpdate = "availableUpdate"
    }

    /// The defaults domain used while `--assume-version` is given, so trying the flow by hand leaves the real
    /// schedule and the stored update alone.
    public static let assumedVersionSuite = "com.burakseyitkara.trrek.assumed-version"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last successful check.
    public var lastCheck: Date? {
        get { defaults.object(forKey: Key.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCheck) }
    }

    /// The last failed check; cleared by a successful one.
    public var lastFailure: Date? {
        get { defaults.object(forKey: Key.lastFailure) as? Date }
        set { defaults.set(newValue, forKey: Key.lastFailure) }
    }

    /// The newer release the last check found. Unreadable data, and a release whose links are not trrek's own
    /// (`ReleaseInfo.hasExpectedLinks`; the defaults can be written by anything running as the user), read as none.
    public var availableUpdate: ReleaseInfo? {
        get {
            guard let data = defaults.data(forKey: Key.availableUpdate),
                  let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data),
                  release.hasExpectedLinks
            else { return nil }
            return release
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.availableUpdate)
                return
            }
            defaults.set(data, forKey: Key.availableUpdate)
        }
    }
}
