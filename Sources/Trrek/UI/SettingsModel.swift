import Observation
import TrrekAppCore

/// The app's settings model; spelled out because SwiftUI has a `Settings` scene type of its own.
typealias AppSettings = TrrekAppCore.Settings

/// What the settings window shows and edits. Exists only while the window is open.
///
/// Every change the window makes to `settings` is passed to `onChange`, which stores and applies it.
@MainActor
@Observable
final class SettingsModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue, !isRefreshing else { return }
            onChange(settings)
        }
    }

    let backlightAvailable: Bool
    /// Whether the DDC/CI bridge exists on this Mac; without it the External Monitor Brightness toggle is disabled.
    let externalBrightnessAvailable: Bool
    var accessibilityGranted: Bool
    var selectedTab: SettingsTab = .general

    /// Whether the Reset to Defaults confirmation is showing. Window state lives here rather than in view state,
    /// so it goes away with the window.
    var confirmingReset = false
    /// The bundle ID of the selected row in the paused apps list.
    var selectedPausedApp: String?

    @ObservationIgnored private let onChange: (AppSettings) -> Void
    @ObservationIgnored private var isRefreshing = false

    init(
        settings: AppSettings,
        backlightAvailable: Bool,
        externalBrightnessAvailable: Bool = true,
        accessibilityGranted: Bool = false,
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.backlightAvailable = backlightAvailable
        self.externalBrightnessAvailable = externalBrightnessAvailable
        self.accessibilityGranted = accessibilityGranted
        self.onChange = onChange
    }

    /// Shows settings changed elsewhere (the menu bar menu) without passing them back to `onChange`.
    func refresh(from settings: AppSettings) {
        isRefreshing = true
        self.settings = settings
        isRefreshing = false
    }

    /// Restores the defaults, keeping Launch at Login and whether the welcome window was shown.
    func resetToDefaults() {
        settings = settings.resetToDefaults(backlightAvailable: backlightAvailable)
    }
}
