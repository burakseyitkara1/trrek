import Testing
import TrrekAppCore
import TrrekEngine

@Test func welcomeCardsForDefaults() {
    let cards = WelcomeContent.cards(for: Settings(), backlightAvailable: true, accessibilityTrusted: true)
    #expect(cards.map(\.title) == [
        "Right edge — Volume",
        "Left edge — Brightness",
        "Top edge — Switch Apps",
        "Bottom edge — Keyboard Backlight"
    ])
    #expect(cards.map(\.edge) == [.right, .left, .top, .bottom])
    #expect(cards.map(\.action) == [.volume, .brightness, .switchApps, .keyboardBacklight])
    #expect(cards.allSatisfy { !$0.detail.isEmpty && !$0.needsAccessibility })
}

@Test func welcomeCardsFollowTheSideEdges() {
    var settings = Settings()
    settings.leftEdge = .volume
    settings.rightEdge = .brightness
    let cards = WelcomeContent.cards(for: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(cards.map(\.title).prefix(2) == ["Right edge — Brightness", "Left edge — Volume"])
}

@Test func welcomeCardsDescribeEveryAction() {
    for action in EdgeAction.allCases {
        var settings = Settings()
        settings.rightEdge = action
        let card = WelcomeContent.cards(for: settings, backlightAvailable: true, accessibilityTrusted: true)[0]
        #expect(card.title == "Right edge — \(SettingsLabels.title(for: action))")
        #expect(!card.detail.isEmpty)
    }
}

@Test func welcomeCardsWithoutBacklightShowMedia() {
    let cards = WelcomeContent.cards(for: Settings(), backlightAvailable: false, accessibilityTrusted: true)
    #expect(cards.last?.title == "Bottom edge — Media")
    #expect(cards.last?.action == .media)
}

@Test func welcomeCardsWithoutAccessibilityNameTheActionAndTheNeed() {
    let cards = WelcomeContent.cards(for: Settings(), backlightAvailable: true, accessibilityTrusted: false)
    #expect(cards.map(\.action) == [.volume, .brightness, .switchApps, .keyboardBacklight])
    #expect(cards.map(\.needsAccessibility) == [true, true, true, false])
    #expect(cards[0].detail == "Needs Accessibility access.")
    #expect(cards[3].detail == "Slide to brighten or dim the keys.")
}
