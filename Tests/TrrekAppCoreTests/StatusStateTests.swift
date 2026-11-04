import Testing
import TrrekAppCore

@Test func statusTextCoversEveryState() {
    #expect(StatusText.text(trackpadIssue: .notFound, accessibilityTrusted: true, pausedAppName: nil)
        == "Trackpad not found")
    #expect(StatusText.text(trackpadIssue: .dataUnavailable, accessibilityTrusted: true, pausedAppName: nil)
        == "Trackpad data unavailable")
    #expect(StatusText.text(trackpadIssue: nil, accessibilityTrusted: false, pausedAppName: nil)
        == "Accessibility access needed")
    #expect(StatusText.text(trackpadIssue: nil, accessibilityTrusted: true, pausedAppName: "Game")
        == "Paused in Game")
    #expect(StatusText.text(trackpadIssue: nil, accessibilityTrusted: true, pausedAppName: nil)
        == "trrek is active")
}

@Test func statusTextPriority() {
    // A trackpad issue outranks everything, missing Accessibility outranks a paused app.
    #expect(StatusText.text(trackpadIssue: .notFound, accessibilityTrusted: false, pausedAppName: "Game")
        == "Trackpad not found")
    #expect(StatusText.text(trackpadIssue: .dataUnavailable, accessibilityTrusted: false, pausedAppName: "Game")
        == "Trackpad data unavailable")
    #expect(StatusText.text(trackpadIssue: nil, accessibilityTrusted: false, pausedAppName: "Game")
        == "Accessibility access needed")
}

@Test func frontmostAppDecidesThePause() {
    var pause = FrontmostPause()
    #expect(!pause.isPaused(in: ["com.example.game"]))
    pause.activated(bundleID: "com.example.game", isOwnApp: false)
    #expect(pause.isPaused(in: ["com.example.game"]))
    pause.activated(bundleID: "com.example.editor", isOwnApp: false)
    #expect(!pause.isPaused(in: ["com.example.game"]))
    // An application without a bundle ID is never paused.
    pause.activated(bundleID: nil, isOwnApp: false)
    #expect(!pause.isPaused(in: ["com.example.game"]))
}

@Test func ownAppKeepsThePreviousAppsPauseState() {
    var pause = FrontmostPause()
    pause.activated(bundleID: "com.example.game", isOwnApp: false)
    // trrek's settings window comes to the front over the paused game.
    pause.activated(bundleID: "com.burakseyitkara.trrek", isOwnApp: true)
    #expect(pause.bundleID == "com.example.game")
    #expect(pause.isPaused(in: ["com.example.game"]))
    // Removing the game from the list in that window takes effect at once.
    #expect(!pause.isPaused(in: []))

    pause.activated(bundleID: "com.example.editor", isOwnApp: false)
    pause.activated(bundleID: "com.burakseyitkara.trrek", isOwnApp: true)
    #expect(!pause.isPaused(in: ["com.example.game"]))
}
