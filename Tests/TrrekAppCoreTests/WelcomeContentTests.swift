import Testing
import TrrekAppCore
import TrrekEngine

@Test func welcomeCardsForDefaults() {
    let cards = WelcomeContent.cards(for: Settings(), backlightAvailable: true)
    #expect(cards.map(\.title) == [
        "Right edge — Volume",
        "Left edge — Brightness",
        "Top edge — Switch Apps",
        "Bottom edge — Keyboard Backlight"
    ])
    #expect(cards.map(\.edge) == [.right, .left, .top, .bottom])
    #expect(cards.map(\.action) == [.volume, .brightness, .switchApps, .keyboardBacklight])
    #expect(cards.allSatisfy { !$0.detail.isEmpty })
}

@Test func welcomeCardsFollowSwapSides() {
    var settings = Settings()
    settings.swapSides = true
    let cards = WelcomeContent.cards(for: settings, backlightAvailable: true)
    #expect(cards.map(\.title).prefix(2) == ["Right edge — Brightness", "Left edge — Volume"])
}

@Test func welcomeCardsWithoutBacklightShowMedia() {
    let cards = WelcomeContent.cards(for: Settings(), backlightAvailable: false)
    #expect(cards.last?.title == "Bottom edge — Media")
    #expect(cards.last?.action == .media)
}
