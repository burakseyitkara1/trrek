import Foundation
import TrrekAppCore

/// The interface language: the `AppleLanguages` preference follows the language setting.
extension Coordinator {
    /// The localization this launch shows, chosen by Foundation from the preferences at launch.
    static var launchLocalization: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// `loaded` with its language and the `AppleLanguages` preference brought into agreement, run once at launch.
    ///
    /// Every change of the setting writes the preference at once (`languageChanged`), so a preference that names a
    /// language other than the setting's was written elsewhere: by the per-app language in System Settings (or by
    /// hand). The setting adopts it and is saved; the interface already shows it. Otherwise the preference is written
    /// to match the setting (for example when it is missing for a chosen language) and takes effect at the next
    /// launch; until then the General tab offers to relaunch.
    func reconciledLanguage(_ loaded: Settings) -> Settings {
        var settings = loaded
        if let adopted = LanguagePreference.adoptedLanguage(
            fromStored: languagePreference.stored,
            setting: settings.language
        ) {
            settings.language = adopted
            store.save(settings)
            appLogger.notice("language setting follows the preference: \(adopted.rawValue, privacy: .public)")
        }
        let language = settings.language
        if languagePreference.apply(language) {
            appLogger.notice("language preference set to \(language.rawValue, privacy: .public)")
        }
        return settings
    }

    /// Writes the preference for a new language setting; the interface changes at the next launch.
    func languageChanged(to language: AppLanguage) {
        languagePreference.apply(language)
        appLogger.notice("language set to \(language.rawValue, privacy: .public) for the next launch")
    }
}
