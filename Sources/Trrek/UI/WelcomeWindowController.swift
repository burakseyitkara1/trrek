import AppKit
import SwiftUI

/// Creates the welcome window on demand and releases it, its hosting controller and its model when it closes.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let contentSize = CGSize(width: 560, height: 440)

    private let registry: WindowRegistry

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    /// Brings the open window to the front, or builds a new one around `model`.
    func show(model: WelcomeModel) {
        let window = registry.welcomeWindow ?? makeWindow(model: model)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        registry.welcomeWindow?.close()
    }

    private func makeWindow(model: WelcomeModel) -> NSWindow {
        let window = ShortcutClosingWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to trrek", bundle: .main)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        model.close = { [weak self] in self?.close() }
        window.contentViewController = NSHostingController(rootView: WelcomeView(model: model))
        window.setContentSize(Self.contentSize)
        window.center()
        window.delegate = self
        model.trackpadSize = registry.trackpadSize ?? model.trackpadSize
        registry.welcomeWindow = window
        registry.welcomeModel = model
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === registry.welcomeWindow else { return }
        window.delegate = nil
        window.contentViewController = nil
        registry.welcomeWindow = nil
        registry.welcomeModel?.close = {}
        registry.welcomeModel = nil
    }
}
