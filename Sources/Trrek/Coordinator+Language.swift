import Foundation
import TrrekAppCore

/// The interface language: the `AppleLanguages` preference follows the language setting.
extension Coordinator {
    /// The localization this launch shows, chosen by Foundation from the preferences at launch.
    static var launchLocalization: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Makes the `AppleLanguages` preference match the language setting.
    /// Every change of the setting writes the preference at once (`languageChanged`), but the two can still disagree
    /// at launch, for example when the defaults were edited by hand or trrek stopped between the two writes. The
    /// preference is then written to match the setting and takes effect at the next launch; until then the General
    /// tab offers to relaunch.
    func reconcileLanguage() {
        let language = settings.language
        if languagePreference.apply(language) {
            appLogger.notice("language preference set to \(language.rawValue, privacy: .public)")
        }
    }

    /// Writes the preference for a new language setting; the interface changes at the next launch.
    func languageChanged(to language: AppLanguage) {
        languagePreference.apply(language)
        appLogger.notice("language set to \(language.rawValue, privacy: .public) for the next launch")
    }
}
