import Observation
import TrrekAppCore

/// What the welcome window shows. Exists only while the window is open; the coordinator keeps the settings and
/// the Accessibility state current.
@MainActor
@Observable
final class WelcomeModel {
    var settings: AppSettings
    let backlightAvailable: Bool
    var accessibilityGranted: Bool

    @ObservationIgnored let grantAccessibility: () -> Void
    @ObservationIgnored let openSettings: () -> Void
    /// Closes the window; set by the window controller.
    @ObservationIgnored var close: () -> Void = {}

    init(
        settings: AppSettings,
        backlightAvailable: Bool,
        accessibilityGranted: Bool,
        grantAccessibility: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.backlightAvailable = backlightAvailable
        self.accessibilityGranted = accessibilityGranted
        self.grantAccessibility = grantAccessibility
        self.openSettings = openSettings
    }

    var cards: [WelcomeCard] {
        WelcomeContent.cards(
            for: settings,
            backlightAvailable: backlightAvailable,
            accessibilityTrusted: accessibilityGranted
        )
    }
}
