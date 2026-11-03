import AppKit

/// Holds the app's on-demand windows while they are open; each is released when it closes.
@MainActor
final class WindowRegistry {
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?
}
