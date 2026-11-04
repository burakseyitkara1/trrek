import Testing
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

@Test func edgeLabelsAndSymbols() {
    #expect(SettingsLabels.title(for: EdgeAction.volume) == "Volume")
    #expect(SettingsLabels.title(for: EdgeAction.brightness) == "Brightness")
    #expect(SettingsLabels.title(for: EdgeAction.switchApps) == "Switch Apps")
    #expect(SettingsLabels.title(for: EdgeAction.scrubVideo) == "Scrub Video")
    #expect(SettingsLabels.title(for: EdgeAction.keyboardBacklight) == "Keyboard Backlight")
    #expect(SettingsLabels.title(for: EdgeAction.media) == "Media")
    #expect(SettingsLabels.title(for: EdgeAction.off) == "Off")
    #expect(SettingsLabels.symbol(for: EdgeAction.volume) == "speaker.wave.2")
    #expect(SettingsLabels.symbol(for: EdgeAction.brightness) == "sun.max")
    #expect(SettingsLabels.symbol(for: EdgeAction.keyboardBacklight) == "keyboard")
    #expect(SettingsLabels.symbol(for: EdgeAction.switchApps) == "rectangle.on.rectangle")
    #expect(SettingsLabels.symbol(for: EdgeAction.media) == "play")
    #expect(SettingsLabels.symbol(for: EdgeAction.off) == nil)
}

@Test func cornerLabelsSymbolsAndCycle() {
    #expect(SettingsLabels.title(for: CornerAction.off) == "Off")
    #expect(SettingsLabels.title(for: CornerAction.mute) == "Mute")
    #expect(SettingsLabels.title(for: CornerAction.screenshot) == "Screenshot")
    #expect(SettingsLabels.symbol(for: CornerAction.off) == nil)
    #expect(SettingsLabels.symbol(for: CornerAction.mute) == "speaker.slash")
    #expect(SettingsLabels.symbol(for: CornerAction.screenshot) == "camera.viewfinder")
    #expect(SettingsLabels.next(after: .off) == .mute)
    #expect(SettingsLabels.next(after: .mute) == .screenshot)
    #expect(SettingsLabels.next(after: .screenshot) == .off)
}

@Test func optionTitles() {
    #expect(HapticStrength.allCases.map(SettingsLabels.title(for:)) == ["Off", "Light", "Medium", "Strong"])
    #expect(EdgeWidth.allCases.map(SettingsLabels.title(for:)) == ["Narrow", "Standard", "Wide"])
    #expect(HoldKey.allCases.map(SettingsLabels.title(for:)) == ["None", "Shift", "Control", "Option", "Command"])
    #expect(HoldKeyMode.allCases.map(SettingsLabels.title(for:)) == ["Hold", "Toggle"])
    #expect(Corner.allCases.map(SettingsLabels.title(for:)) == ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
}

@Test func topAndBottomChoicesMatchSpec() {
    #expect(EdgeChoices.topAndBottom == [.switchApps, .scrubVideo, .keyboardBacklight, .media, .off])
    #expect(!EdgeChoices.isSelectable(.scrubVideo, backlightAvailable: true))
    #expect(EdgeChoices.isSelectable(.keyboardBacklight, backlightAvailable: true))
    #expect(!EdgeChoices.isSelectable(.keyboardBacklight, backlightAvailable: false))
    #expect(EdgeChoices.isSelectable(.media, backlightAvailable: false))
    #expect(EdgeChoices.caption(for: .scrubVideo, backlightAvailable: true) == "Coming later")
    #expect(EdgeChoices.caption(for: .keyboardBacklight, backlightAvailable: false) == "Not available on this Mac")
    #expect(EdgeChoices.caption(for: .keyboardBacklight, backlightAvailable: true) == nil)
    #expect(EdgeChoices.displayed(.keyboardBacklight, backlightAvailable: false) == .media)
    #expect(EdgeChoices.displayed(.keyboardBacklight, backlightAvailable: true) == .keyboardBacklight)
    #expect(EdgeChoices.displayed(.switchApps, backlightAvailable: false) == .switchApps)
}

@Test func diagramEdgesFollowSettings() {
    var settings = Settings()
    var edges = DiagramEdges(settings: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(edges == DiagramEdges(left: .brightness, right: .volume, top: .switchApps, bottom: .keyboardBacklight))

    edges = DiagramEdges(settings: settings, backlightAvailable: false, accessibilityTrusted: true)
    #expect(edges.bottom == .media)

    settings.swapSides = true
    settings.topEdge = .scrubVideo
    settings.bottomEdge = .off
    edges = DiagramEdges(settings: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(edges == DiagramEdges(left: .volume, right: .brightness, top: .off, bottom: .off))
}

@Test func diagramEdgesShowTheGatedActions() {
    let edges = DiagramEdges(settings: Settings(), backlightAvailable: true, accessibilityTrusted: false)
    #expect(edges == DiagramEdges(left: .off, right: .off, top: .off, bottom: .keyboardBacklight))
}

@Test func accessibilityNeededNamesTheControls() {
    #expect(SettingsLabels.accessibilityNeeded
        == "trrek needs Accessibility access to change volume, brightness and the other controls.")
}

@Test func cornerSubscriptReadsAndWritesEachCorner() {
    var settings = Settings()
    settings[corner: .topLeft] = .mute
    settings[corner: .topRight] = .screenshot
    settings[corner: .bottomLeft] = .screenshot
    settings[corner: .bottomRight] = .mute
    #expect(settings.topLeft == .mute)
    #expect(settings.topRight == .screenshot)
    #expect(settings.bottomLeft == .screenshot)
    #expect(settings.bottomRight == .mute)
    #expect(Corner.allCases.map { settings[corner: $0] } == [.mute, .screenshot, .screenshot, .mute])
}

@Test func resetKeepsLaunchStateAndFallsBackWithoutBacklight() {
    var settings = Settings()
    settings.precision = true
    settings.topLeft = .mute
    settings.pausedBundleIDs = ["com.example.one"]
    settings.launchAtLogin = false
    settings.welcomeShown = true

    let reset = settings.resetToDefaults(backlightAvailable: true)
    var expected = Settings()
    expected.launchAtLogin = false
    expected.welcomeShown = true
    #expect(reset == expected)

    let withoutBacklight = settings.resetToDefaults(backlightAvailable: false)
    #expect(withoutBacklight.bottomEdge == .media)
    #expect(!withoutBacklight.launchAtLogin)
    #expect(withoutBacklight.welcomeShown)
}

@Test func settingsTabParsesArguments() {
    #expect(SettingsTab(argument: "general") == .general)
    #expect(SettingsTab(argument: "edges") == .edges)
    #expect(SettingsTab(argument: "corners") == .corners)
    #expect(SettingsTab(argument: "Advanced") == .advanced)
    #expect(SettingsTab(argument: "other") == nil)
    #expect(SettingsTab(argument: nil) == nil)
    #expect(SettingsTab.allCases.map(\.title) == ["General", "Edges", "Corners & Taps", "Advanced"])
}
