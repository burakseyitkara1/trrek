import AppKit
import SwiftUI

/// Creates the settings window on demand and releases it, its hosting controller and its model when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let contentSize = CGSize(width: 640, height: 480)

    private let registry: WindowRegistry

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    /// Brings the open window to the front, or builds a new one around `model`.
    func show(model: SettingsModel) {
        let window = registry.settingsWindow ?? makeWindow(model: model)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: SettingsModel) -> NSWindow {
        let window = ShortcutClosingWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "trrek Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.setContentSize(Self.contentSize)
        window.center()
        window.delegate = self
        registry.settingsWindow = window
        registry.settingsModel = model
        return window
    }

    /// Drops every reference trrek holds. SwiftUI releases the model when it tears down the view graph, on the
    /// next turn of the main actor.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === registry.settingsWindow else { return }
        window.delegate = nil
        window.contentViewController = nil
        registry.settingsWindow = nil
        registry.settingsModel = nil
    }
}

/// Closes on ⌘W; the app has no main menu to provide it.
final class ShortcutClosingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
