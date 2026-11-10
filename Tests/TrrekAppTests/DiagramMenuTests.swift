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

    @Test func allAppsEdgesListOffFirstThenEveryAction() {
        let model = Self.model()
        let order: [EdgeAction] = [.off] + EdgeChoices.all.filter { $0 != .off }
        for edge in Edge.allCases {
            let options = model.edgeMenuOptions(for: edge)
            #expect(options.map(\.action) == order)
            #expect(options.first?.action == .off)
            #expect(options.map(\.symbol) == order.map(SettingsLabels.symbol(for:)))
            #expect(!options.contains { !$0.isEnabled })
        }
        let titles = model.edgeMenuOptions(for: .left).map(\.title)
        #expect(titles.first == "Off")
        #expect(titles.dropFirst().first == "Volume")
        #expect(titles.contains("Scrub Video — Uses ← and → in the front app"))
        #expect(titles.contains("Off"))
    }

    @Test func cornerMenusListOffFirst() {
        #expect(Self.model().cornerMenuOptions.first == .off)
        #expect(Set(Self.model().cornerMenuOptions) == Set(CornerAction.allCases))
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
        #expect(options.dropFirst().map(\.action) == [.off] + EdgeChoices.all.filter { $0 != .off })
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

    // MARK: - Scope details

    @Test func bothNotesShowWhenTheBacklightAndAccessibilityAreMissing() {
        let model = Self.model(backlight: false, accessibility: false)
        let bottom = model.diagramEdge(.bottom)
        #expect(bottom.action == .media)
        #expect(bottom.notes == [.needsAccessibility, .backlightUnavailable])
        #expect(bottom.note == .needsAccessibility)
        // Only the fallback while Accessibility is granted.
        model.accessibilityGranted = true
        #expect(model.diagramEdge(.bottom).notes == [.backlightUnavailable])
    }

    @Test func theAccessibilityNoteFollowsTheShownScope() {
        var settings = AppSettings()
        for edge in Edge.allCases {
            settings[edge: edge] = .keyboardBacklight
        }
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]
        let model = Self.model(settings, accessibility: false)
        // All Apps runs only the keyboard backlight, which needs no Accessibility; the app's own top edge does.
        #expect(!model.diagramEdgesNeedAccessibility)
        model.edgeScope = Self.browser
        #expect(model.diagramEdgesNeedAccessibility)
        #expect(model.diagramEdge(.top).note == .needsAccessibility)
        #expect(model.diagramEdge(.left).note == nil)

        // The other way round: an inherited gated edge is marked, an app's own keyboard backlight is not.
        var other = AppSettings()
        other.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, right: .keyboardBacklight)]
        let scoped = Self.model(other, accessibility: false)
        scoped.edgeScope = Self.browser
        #expect(scoped.diagramEdge(.right).note == nil)
        #expect(scoped.diagramEdge(.left).isInherited)
        #expect(scoped.diagramEdge(.left).note == .needsAccessibility)
        #expect(scoped.diagramEdgesNeedAccessibility)
    }

    @Test func theInheritedItemFollowsTheBacklightFallback() {
        var settings = AppSettings()
        settings.bottomEdge = .keyboardBacklight
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = Self.model(settings, backlight: false)
        model.edgeScope = Self.browser
        #expect(model.edgeMenuOptions(for: .bottom).first?.title == "Same as All Apps (Media)")
        let bottom = model.diagramEdge(.bottom)
        #expect(bottom.isInherited)
        #expect(bottom.action == .media)
        #expect(bottom.valueTitle == "Same as All Apps (Media)")
        #expect(bottom.notes == [.backlightUnavailable])
        #expect(model.edgeMenuSelection(for: .bottom) == nil)
    }

    @Test func anAppsOwnActionEqualToAllAppsStaysItsOwn() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = Self.model(settings)
        model.edgeScope = Self.browser
        model.chooseEdgeAction(.switchApps, for: .top)
        #expect(model.settings.edgeProfile(for: Self.browser)?.top == .switchApps)
        #expect(model.edgeMenuSelection(for: .top) == .switchApps)
        #expect(!model.diagramEdge(.top).isInherited)
        #expect(model.diagramEdge(.top).valueTitle == "Switch Apps")
        // It keeps it when All Apps changes.
        model.edgeScope = nil
        model.chooseEdgeAction(.volume, for: .top)
        model.edgeScope = Self.browser
        #expect(model.diagramEdge(.top).action == .switchApps)
    }

    // MARK: - Hover

    @Test func theHoverStateIsClearedWhenItsEndCannotArrive() {
        let model = Self.model()
        model.selectedTab = .edges
        model.hoveredDiagramControl = .edge(.left)
        model.selectedTab = .corners
        #expect(model.hoveredDiagramControl == nil)

        model.hoveredDiagramControl = .edge(.left)
        model.chooseEdgeAction(.zoom, for: .left)
        #expect(model.hoveredDiagramControl == nil)

        model.hoveredDiagramControl = .corner(.topLeft)
        model.chooseCornerAction(.mute, for: .topLeft)
        #expect(model.hoveredDiagramControl == nil)
    }
}
