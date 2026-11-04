import AppKit
import Testing
@testable import Trrek

/// The welcome window is built on demand and released, with its model, when it closes.
@MainActor
struct WelcomeWindowTests {
    @Test func doneReleasesWindowAndModel() async throws {
        _ = NSApplication.shared
        let registry = WindowRegistry()
        let controller = WelcomeWindowController(registry: registry)
        weak var weakModel: WelcomeModel?
        weak var weakWindow: NSWindow?

        autoreleasepool {
            let model = WelcomeModel(settings: AppSettings(), backlightAvailable: true, accessibilityGranted: false)
            weakModel = model
            controller.show(model: model)
            weakWindow = registry.welcomeWindow
            #expect(registry.welcomeModel === model)
            // The content runs under the transparent title bar.
            let size = registry.welcomeWindow.map { $0.contentRect(forFrameRect: $0.frame).size }
            #expect(size == WelcomeWindowController.contentSize)

            // A second request reuses the open window.
            controller.show(model: model)
            #expect(registry.welcomeWindow === weakWindow)

            // "Done" closes the window through the model.
            model.close()
        }
        #expect(registry.welcomeWindow == nil)
        #expect(registry.welcomeModel == nil)

        // SwiftUI tears its view graph down on later turns of the main queue.
        try await waitUntil { weakModel == nil && weakWindow == nil }
        #expect(weakModel == nil)
        #expect(weakWindow == nil)
    }

    @Test func cardsComeInAfterTheWindowShows() async throws {
        _ = NSApplication.shared
        let registry = WindowRegistry()
        let controller = WelcomeWindowController(registry: registry)
        let model = WelcomeModel(
            settings: AppSettings(), backlightAvailable: true, accessibilityGranted: true, reduceMotion: false
        )
        #expect(!model.cardsVisible)
        controller.show(model: model)
        // The window first draws the cards hidden; they come in on the next turn of the main queue.
        #expect(!model.cardsVisible)
        try await waitUntil { model.cardsVisible }
        #expect(model.cardsVisible)
        model.close()
    }

    @Test func reduceMotionShowsTheCardsAtOnce() {
        let model = WelcomeModel(
            settings: AppSettings(), backlightAvailable: true, accessibilityGranted: true, reduceMotion: true
        )
        #expect(model.cardsVisible)
    }
}
