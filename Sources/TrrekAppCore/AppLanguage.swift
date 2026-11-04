import Foundation

/// The language trrek's interface uses.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    /// The first of the system's preferred languages that trrek has, otherwise English.
    case system
    case english
    case turkish

    /// The name the language picker shows: each language in its own language, and "System" in the current one.
    public var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .main)
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }
}

/// The app's `AppleLanguages` preference, which picks the localization Foundation loads at launch.
///
/// trrek writes the preference into its own defaults domain: a language other than `system` stores that one language,
/// and `system` removes the key so the system's own list applies. The preference is read once per launch, so a change
/// takes effect when trrek is next opened.
public enum LanguagePreference {
    /// The defaults key Foundation reads the preferred languages from.
    public static let key = "AppleLanguages"

    /// What to do to the stored preference.
    public enum Change: Equatable, Sendable {
        /// The stored value already matches.
        case none
        /// Store these language codes.
        case set([String])
        /// Remove the key, so the system's languages apply.
        case remove
    }

    /// The value stored for `language`; `nil` means the key is absent.
    public static func storedValue(for language: AppLanguage) -> [String]? {
        switch language {
        case .system: nil
        case .english: ["en"]
        case .turkish: ["tr"]
        }
    }

    /// The change that makes `stored` (the value in trrek's own domain, `nil` when absent) select `language`.
    public static func change(from stored: Any?, to language: AppLanguage) -> Change {
        let wanted = storedValue(for: language)
        let current = stored.map { $0 as? [String] ?? [] }
        guard current != wanted else { return .none }
        if let wanted {
            return .set(wanted)
        }
        return .remove
    }

    /// The localization (`"en"`, `"tr"`) `language` shows: English or Turkish as chosen, or for `system` the best of
    /// `available` for the system's preferred languages (`systemLanguages`, the global `AppleLanguages`), and the
    /// first of `available` when none matches.
    public static func localization(
        for language: AppLanguage,
        available: [String],
        systemLanguages: [String]
    ) -> String {
        switch language {
        case .english: return "en"
        case .turkish: return "tr"
        case .system:
            let fallback = available.first ?? "en"
            guard !systemLanguages.isEmpty, !available.isEmpty else { return fallback }
            return Bundle.preferredLocalizations(from: available, forPreferences: systemLanguages).first ?? fallback
        }
    }
}

/// Reads and writes the `AppleLanguages` preference in one defaults domain.
public final class LanguagePreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let domain: String

    /// `domain` is the persistent domain `defaults` writes to: the bundle ID for `.standard`, the suite name for a
    /// suite.
    public init(defaults: UserDefaults = .standard, domain: String = AppIdentity.bundleID) {
        self.defaults = defaults
        self.domain = domain
    }

    /// The value in this domain only; the global domain and launch arguments are not consulted.
    public var stored: Any? {
        defaults.persistentDomain(forName: domain)?[LanguagePreference.key]
    }

    /// The system's preferred languages: `AppleLanguages` in the global domain, without trrek's own preference.
    public var systemLanguages: [String] {
        defaults.persistentDomain(forName: UserDefaults.globalDomain)?[LanguagePreference.key] as? [String] ?? []
    }

    /// Makes the stored preference select `language`; returns whether it changed.
    @discardableResult
    public func apply(_ language: AppLanguage) -> Bool {
        switch LanguagePreference.change(from: stored, to: language) {
        case .none:
            return false
        case let .set(codes):
            defaults.set(codes, forKey: LanguagePreference.key)
        case .remove:
            defaults.removeObject(forKey: LanguagePreference.key)
        }
        return true
    }
}
