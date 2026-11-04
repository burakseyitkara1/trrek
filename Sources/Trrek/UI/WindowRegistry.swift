import AppKit

/// Holds the app's on-demand windows while they are open; each is released when it closes.
@MainActor
final class WindowRegistry {
    var settingsWindow: NSWindow?
    /// The settings window's model, so changes made elsewhere can be shown in the open window.
    var settingsModel: SettingsModel?
    var welcomeWindow: NSWindow?
}
