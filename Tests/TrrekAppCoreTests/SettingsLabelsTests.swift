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
    #expect(EdgeAction.allCases.map(SettingsLabels.title(for:)) == [
        "Volume", "Brightness", "Keyboard Backlight", "Switch Apps", "Switch Tabs", "Switch Desktops", "Scrub Video",
        "Media", "Zoom", "Undo & Redo", "Off"
    ])
    #expect(EdgeAction.allCases.filter { $0 != .off }.allSatisfy { SettingsLabels.symbol(for: $0) != nil })
}

@Test func cornerLabelsSymbolsAndCycle() {
    #expect(SettingsLabels.title(for: CornerAction.off) == "Off")
    #expect(SettingsLabels.title(for: CornerAction.mute) == "Mute")
    #expect(SettingsLabels.title(for: CornerAction.screenshot) == "Screenshot")
    #expect(SettingsLabels.symbol(for: CornerAction.off) == nil)
    #expect(SettingsLabels.symbol(for: CornerAction.mute) == "speaker.slash")
    #expect(SettingsLabels.symbol(for: CornerAction.screenshot) == "camera.viewfinder")
    #expect(CornerAction.allCases.map(SettingsLabels.title(for:)) == [
        "Off", "Mute", "Screenshot", "Play/Pause", "Mission Control", "App Windows", "Show Desktop", "Spotlight",
        "Lock Screen", "Screenshot Area"
    ])
    #expect(CornerAction.allCases.filter { $0 != .off }.allSatisfy { SettingsLabels.symbol(for: $0) != nil })
    // A badge click moves through every action in order and wraps around to Off.
    var cycled: [CornerAction] = [.off]
    while cycled.count <= CornerAction.allCases.count {
        cycled.append(SettingsLabels.next(after: cycled[cycled.count - 1]))
    }
    #expect(cycled == CornerAction.allCases + [.off])
}

@Test func optionTitles() {
    #expect(HapticStrength.allCases.map(SettingsLabels.title(for:)) == ["Off", "Light", "Medium", "Strong"])
    #expect(EdgeWidth.allCases.map(SettingsLabels.title(for:)) == ["Narrow", "Standard", "Wide"])
    #expect(HoldKey.allCases.map(SettingsLabels.title(for:)) == ["None", "Shift", "Control", "Option", "Command"])
    #expect(HoldKeyMode.allCases.map(SettingsLabels.title(for:)) == ["Hold", "Toggle"])
    #expect(Corner.allCases.map(SettingsLabels.title(for:)) == ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
    #expect(SlideSensitivity.allCases.map(SettingsLabels.title(for:)) == [
        "Very Low", "Low", "Standard", "High", "Very High"
    ])
}

@Test func everyEdgeOffersTheSameChoices() {
    #expect(EdgeChoices.all == [
        .volume, .brightness, .keyboardBacklight, .switchApps, .switchTabs, .switchDesktops, .scrubVideo, .media,
        .zoom, .undoRedo, .off
    ])
    #expect(EdgeChoices.caption(for: .switchTabs, backlightAvailable: true) == "Uses ⌃⇥ and ⌃⇧⇥ in the front app")
    #expect(EdgeChoices.caption(for: .switchDesktops, backlightAvailable: true) == "Uses ⌃← and ⌃→")
    #expect(EdgeChoices.caption(for: .zoom, backlightAvailable: true) == "Uses ⌘= and ⌘− in the front app")
    #expect(EdgeChoices.caption(for: .undoRedo, backlightAvailable: true) == "Uses ⌘Z and ⇧⌘Z in the front app")
    #expect(EdgeChoices.all.filter { $0 != .keyboardBacklight }.allSatisfy {
        EdgeChoices.isSelectable($0, backlightAvailable: false)
    })
    #expect(EdgeChoices.isSelectable(.scrubVideo, backlightAvailable: true))
    #expect(EdgeChoices.isSelectable(.keyboardBacklight, backlightAvailable: true))
    #expect(!EdgeChoices.isSelectable(.keyboardBacklight, backlightAvailable: false))
    #expect(EdgeChoices.isSelectable(.media, backlightAvailable: false))
    #expect(EdgeChoices.caption(for: .scrubVideo, backlightAvailable: true) == "Uses ← and → in the front app")
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

    settings.leftEdge = .volume
    settings.rightEdge = .brightness
    settings.topEdge = .scrubVideo
    settings.bottomEdge = .off
    edges = DiagramEdges(settings: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(edges == DiagramEdges(left: .volume, right: .brightness, top: .scrubVideo, bottom: .off))

    settings.leftEdge = .keyboardBacklight
    settings.rightEdge = .switchDesktops
    edges = DiagramEdges(settings: settings, backlightAvailable: false, accessibilityTrusted: true)
    #expect(edges.left == .media)
    #expect(edges.right == .switchDesktops)
}

@Test func edgeSubscriptReadsAndWritesEachEdge() {
    var settings = Settings()
    settings[edge: .left] = .zoom
    settings[edge: .right] = .undoRedo
    settings[edge: .top] = .switchTabs
    settings[edge: .bottom] = .switchDesktops
    #expect(settings.leftEdge == .zoom)
    #expect(settings.rightEdge == .undoRedo)
    #expect(settings.topEdge == .switchTabs)
    #expect(settings.bottomEdge == .switchDesktops)
    #expect(Edge.allCases.map { settings[edge: $0] } == [.zoom, .undoRedo, .switchTabs, .switchDesktops])
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

@Test func scrubVideoIsSelectable() {
    #expect(EdgeChoices.isSelectable(.scrubVideo, backlightAvailable: false))
    #expect(EdgeChoices.isSelectable(.scrubVideo, backlightAvailable: true))
}

@Test func externalBrightnessCaptionSaysWhenUnavailable() {
    #expect(SettingsLabels.externalBrightnessCaption(available: true) == SettingsLabels.externalBrightnessCaption)
    #expect(SettingsLabels.externalBrightnessCaption(available: false) == "Not available on this Mac")
}
