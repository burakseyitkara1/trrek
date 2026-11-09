import AppKit
import Observation
import SwiftUI
import TrrekAppCore

/// What the welcome window shows. Exists only while the window is open; the coordinator keeps the settings and
/// the Accessibility state current.
@MainActor
@Observable
final class WelcomeModel {
    var settings: AppSettings
    let backlightAvailable: Bool
    var accessibilityGranted: Bool
    /// This Mac's trackpad, which the diagram's edge zones are drawn to scale with; `nil` while trrek knows none.
    var trackpadSize: TrackpadSize?
    /// Whether the edge cards are on screen. Starts off so they can appear one after another once the window is
    /// up; starts on when Reduce Motion is set, so they are simply there.
    private(set) var cardsVisible: Bool

    @ObservationIgnored let grantAccessibility: () -> Void
    @ObservationIgnored let openSettings: () -> Void
    /// Closes the window; set by the window controller.
    @ObservationIgnored var close: () -> Void = {}

    init(
        settings: AppSettings,
        backlightAvailable: Bool,
        accessibilityGranted: Bool,
        trackpadSize: TrackpadSize? = nil,
        grantAccessibility: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {},
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        self.settings = settings
        self.backlightAvailable = backlightAvailable
        self.accessibilityGranted = accessibilityGranted
        self.trackpadSize = trackpadSize
        self.grantAccessibility = grantAccessibility
        self.openSettings = openSettings
        cardsVisible = reduceMotion
    }

    /// Brings the cards in; each card adds its own delay (`cardDelay` per position). Does nothing once they show.
    func revealCards() {
        guard !cardsVisible else { return }
        withAnimation(.smooth) {
            cardsVisible = true
        }
    }

    /// Time between one card appearing and the next.
    static let cardDelay: TimeInterval = 0.08

    var cards: [WelcomeCard] {
        WelcomeContent.cards(
            for: settings,
            backlightAvailable: backlightAvailable,
            accessibilityTrusted: accessibilityGranted
        )
    }
}
