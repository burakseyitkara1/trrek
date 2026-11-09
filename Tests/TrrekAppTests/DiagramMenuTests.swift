import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine

/// The trackpad diagram's edge and corner menus in the Edges and Corners & Taps tabs.
@MainActor
struct DiagramMenuTests {
    private static let browser = "com.example.browser"

    private static func model(
        _ settings: AppSettings = AppSettings(),
        backlight: Bool = true,
        accessibility: Bool = true,
        onChange: @escaping (AppSettings) -> Void = { _ in }
    ) -> SettingsModel {
        SettingsModel(
            settings: settings,
            backlightAvailable: backlight,
            accessibilityGranted: accessibility,
            onChange: onChange
        )
    }

    // MARK: - Edge menus

    @Test func allAppsEdgesListEveryActionWithOffLast() {
        let model = Self.model()
        for edge in Edge.allCases {
            let options = model.edgeMenuOptions(for: edge)
            #expect(options.map(\.action) == EdgeChoices.all)
            #expect(options.last?.action == .off)
            #expect(options.map(\.symbol) == EdgeChoices.all.map(SettingsLabels.symbol(for:)))
            #expect(!options.contains { !$0.isEnabled })
        }
        let titles = model.edgeMenuOptions(for: .left).map(\.title)
        #expect(titles.first == "Volume")
        #expect(titles.contains("Scrub Video — Uses ← and → in the front app"))
        #expect(titles.contains("Off"))
    }

    @Test func theKeyboardBacklightCannotBeChosenWithoutItsBridge() throws {
        let options = Self.model(backlight: false).edgeMenuOptions(for: .bottom)
        let backlight = try #require(options.first { $0.action == .keyboardBacklight })
        #expect(!backlight.isEnabled)
        #expect(backlight.title == "Keyboard Backlight — Not available on this Mac")
        #expect(!options.contains { $0.action != .keyboardBacklight && !$0.isEnabled })
    }

    @Test func anAppsEdgesStartWithSameAsAllApps() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = Self.model(settings)
        model.edgeScope = Self.browser
        let options = model.edgeMenuOptions(for: .top)
        #expect(options.first == EdgeMenuOption(
            action: nil,
            title: "Same as All Apps (Switch Apps)",
            symbol: nil,
            isEnabled: true
        ))
        #expect(options.dropFirst().map(\.action) == EdgeChoices.all)
    }

    @Test func choosingAnAllAppsEdgeSetsIt() {
        var received: [AppSettings] = []
        let model = Self.model { received.append($0) }
        #expect(model.edgeMenuSelection(for: .left) == .brightness)
        model.chooseEdgeAction(.zoom, for: .left)
        #expect(model.settings.leftEdge == .zoom)
        #expect(model.edgeMenuSelection(for: .left) == .zoom)
        #expect(received.last?.leftEdge == .zoom)
        // All Apps has no Same as All Apps.
        model.chooseEdgeAction(nil, for: .left)
        #expect(model.settings.leftEdge == .zoom)
        #expect(received.count == 1)
    }

    @Test func choosingAnAppsEdgeSetsItsProfileOnly() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = Self.model(settings)
        model.edgeScope = Self.browser
        #expect(model.edgeMenuSelection(for: .top) == nil)

        model.chooseEdgeAction(.switchTabs, for: .top)
        #expect(model.settings.edgeProfile(for: Self.browser)?.top == .switchTabs)
        #expect(model.settings.topEdge == .switchApps)
        #expect(model.edgeMenuSelection(for: .top) == .switchTabs)

        model.chooseEdgeAction(nil, for: .top)
        #expect(model.settings.edgeProfile(for: Self.browser) == AppEdgeProfile(bundleID: Self.browser))
        #expect(model.edgeMenuSelection(for: .top) == nil)
    }

    @Test func anAppsLabelsShowTheEffectiveActionAndWhetherItIsInherited() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]
        let model = Self.model(settings)

        // All Apps: nothing is inherited.
        #expect(Edge.allCases.allSatisfy { !model.diagramEdge($0).isInherited })
        #expect(model.diagramEdge(.top).action == .switchApps)
        #expect(model.diagramEdge(.top).valueTitle == "Switch Apps")

        model.edgeScope = Self.browser
        let top = model.diagramEdge(.top)
        #expect(top.action == .switchTabs)
        #expect(!top.isInherited)
        #expect(top.valueTitle == "Switch Tabs")
        let left = model.diagramEdge(.left)
        #expect(left.action == .brightness)
        #expect(left.isInherited)
        #expect(left.valueTitle == "Same as All Apps (Brightness)")
    }

    // MARK: - Edge notes

    @Test func edgesThatNeedAccessibilityAreMarked() {
        var settings = AppSettings()
        settings.leftEdge = .off
        let model = Self.model(settings, accessibility: false)
        // The label keeps the chosen action; the note says why it does not run.
        #expect(model.diagramEdge(.right).action == .volume)
        #expect(model.diagramEdge(.right).note == .needsAccessibility)
        #expect(model.diagramEdge(.top).note == .needsAccessibility)
        // The keyboard backlight works without Accessibility, and Off needs nothing.
        #expect(model.diagramEdge(.bottom).note == nil)
        #expect(model.diagramEdge(.left).note == nil)
        #expect(model.diagramEdgesNeedAccessibility)
        #expect(DiagramNote.needsAccessibility.text == "Needs Accessibility access")

        model.accessibilityGranted = true
        #expect(Edge.allCases.allSatisfy { model.diagramEdge($0).note == nil })
        #expect(!model.diagramEdgesNeedAccessibility)
    }

    @Test func theKeyboardBacklightFallbackIsMarked() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, left: .keyboardBacklight)]
        let model = Self.model(settings, backlight: false)
        let bottom = model.diagramEdge(.bottom)
        #expect(bottom.action == .media)
        #expect(bottom.note == .backlightUnavailable)
        #expect(model.edgeMenuSelection(for: .bottom) == .media)
        #expect(model.diagramEdge(.right).note == nil)
        #expect(DiagramNote.backlightUnavailable.text == "Keyboard Backlight — Not available on this Mac")

        // An app's own keyboard backlight edge too.
        model.edgeScope = Self.browser
        #expect(model.diagramEdge(.left).action == .media)
        #expect(model.diagramEdge(.left).note == .backlightUnavailable)
        #expect(model.edgeMenuSelection(for: .left) == .media)

        // Without Accessibility, media control needs it: that note comes first.
        model.accessibilityGranted = false
        #expect(model.diagramEdge(.left).note == .needsAccessibility)
    }

    // MARK: - Corners

    @Test func cornerMenusListEveryActionWithOff() {
        let model = Self.model()
        #expect(model.cornerMenuOptions == CornerAction.allCases)
        #expect(model.cornerMenuOptions.contains(.off))
    }

    @Test func choosingACornerActionSetsIt() {
        var received: [AppSettings] = []
        let model = Self.model { received.append($0) }
        model.chooseCornerAction(.spotlight, for: .bottomLeft)
        #expect(model.settings.bottomLeft == .spotlight)
        #expect(model.diagramCorner(.bottomLeft).action == .spotlight)
        model.chooseCornerAction(.off, for: .bottomLeft)
        #expect(model.settings.bottomLeft == .off)
        #expect(received.map(\.bottomLeft) == [.spotlight, .off])
    }

    @Test func cornersThatNeedAccessibilityAreMarked() {
        var settings = AppSettings()
        settings.topLeft = .mute
        let model = Self.model(settings, accessibility: false)
        let topLeft = model.diagramCorner(.topLeft)
        #expect(topLeft.action == .mute)
        #expect(topLeft.note == .needsAccessibility)
        #expect(model.diagramCorner(.topRight).note == nil)
        #expect(model.diagramCornersNeedAccessibility)

        model.accessibilityGranted = true
        #expect(model.diagramCorner(.topLeft).note == nil)
        #expect(!model.diagramCornersNeedAccessibility)
    }

    @Test func edgeAndCornerTitlesNameTheControl() {
        #expect(SettingsLabels.title(for: Edge.left) == "Left Edge")
        #expect(SettingsLabels.title(for: Corner.bottomRight) == "Bottom Right")
    }
}
