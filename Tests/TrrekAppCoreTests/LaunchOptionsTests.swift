import Testing
import TrrekAppCore

@Test func emptyArgumentsYieldNoOptions() {
    let options = LaunchOptions(arguments: ["/path/trrek"])
    #expect(options == LaunchOptions())
}

@Test func settingsTakesAnOptionalTab() {
    let plain = LaunchOptions(arguments: ["trrek", "--settings"])
    #expect(plain.openSettings)
    #expect(plain.settingsTab == nil)

    let tab = LaunchOptions(arguments: ["trrek", "--settings", "edges"])
    #expect(tab.openSettings)
    #expect(tab.settingsTab == "edges")

    let followed = LaunchOptions(arguments: ["trrek", "--settings", "--welcome"])
    #expect(followed.openSettings)
    #expect(followed.settingsTab == nil)
    #expect(followed.welcome)

    let none = LaunchOptions(arguments: ["trrek"])
    #expect(!none.openSettings)
    #expect(none.settingsTab == nil)
}

@Test func flagsAndQuitAfterAreParsed() {
    let options = LaunchOptions(arguments: ["trrek", "--welcome", "--demo-overlay", "--quit-after", "8"])
    #expect(options.welcome)
    #expect(options.demoOverlay)
    #expect(options.quitAfter == 8)
}

@Test func invalidQuitAfterIsIgnored() {
    #expect(LaunchOptions(arguments: ["trrek", "--quit-after"]).quitAfter == nil)
    #expect(LaunchOptions(arguments: ["trrek", "--quit-after", "soon"]).quitAfter == nil)
    #expect(LaunchOptions(arguments: ["trrek", "--quit-after", "-1"]).quitAfter == nil)
}

@Test func skipFirstRunIsParsed() {
    #expect(LaunchOptions(arguments: ["trrek", "--skip-first-run"]).skipFirstRun)
    #expect(!LaunchOptions(arguments: ["trrek"]).skipFirstRun)
    let combined = LaunchOptions(arguments: ["trrek", "--settings", "edges", "--skip-first-run", "--quit-after", "6"])
    #expect(combined.settingsTab == "edges")
    #expect(combined.skipFirstRun)
    #expect(combined.quitAfter == 6)
}
