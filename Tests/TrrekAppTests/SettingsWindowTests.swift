import AppKit
import Testing
@testable import Trrek

/// The settings window is built on demand and released, with its model, when it closes.
@MainActor
struct SettingsWindowTests {
    @Test func closingReleasesWindowAndModel() async throws {
        _ = NSApplication.shared
        let registry = WindowRegistry()
        let controller = SettingsWindowController(registry: registry)
        weak var weakModel: SettingsModel?
        weak var weakWindow: NSWindow?
        weak var weakHost: NSViewController?

        autoreleasepool {
            let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }
            weakModel = model
            controller.show(model: model)
            weakWindow = registry.settingsWindow
            weakHost = registry.settingsWindow?.contentViewController
            #expect(registry.settingsModel === model)
            #expect(registry.settingsWindow?.contentLayoutRect.size == SettingsWindowController.contentSize)

            // A second request reuses the open window.
            controller.show(model: model)
            #expect(registry.settingsWindow === weakWindow)

            registry.settingsWindow?.close()
        }
        #expect(registry.settingsWindow == nil)
        #expect(registry.settingsModel == nil)

        // SwiftUI tears its view graph down, and with it the last reference to the model, on a later main-actor
        // turn. Suspending (rather than only spinning the run loop inside this job) lets that work run.
        let deadline = Date(timeIntervalSinceNow: 10)
        while weakModel != nil || weakWindow != nil || weakHost != nil, Date() < deadline {
            Self.spinRunLoop()
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(weakWindow == nil)
        #expect(weakHost == nil)
        #expect(weakModel == nil)
    }

    /// Runs one short pass of the main run loop, for AppKit work queued on it.
    private static func spinRunLoop() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
}
