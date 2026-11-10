import AppKit

/// Holds the app's on-demand windows while they are open; each is released when it closes.
@MainActor
final class WindowRegistry {
    /// The trackpad the diagrams' edge zones are drawn to scale with: the built-in one, else the first, from the
    /// last start of the multitouch stream that found one; `nil` until then. Shown in the open windows and given
    /// to each new one.
    var trackpadSize: TrackpadSize? {
        didSet {
            settingsModel?.trackpadSize = trackpadSize
            welcomeModel?.trackpadSize = trackpadSize
        }
    }

    var settingsWindow: NSWindow?
    /// The settings window's model, so changes made elsewhere can be shown in the open window.
    var settingsModel: SettingsModel?
    var welcomeWindow: NSWindow?
    /// The welcome window's model, so settings and Accessibility changes show in the open window.
    var welcomeModel: WelcomeModel?
}
