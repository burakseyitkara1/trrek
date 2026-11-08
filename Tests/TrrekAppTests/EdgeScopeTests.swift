import Foundation
import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine

/// The Edges tab's scope: All Apps or one app with edges of its own.
@MainActor
struct EdgeScopeTests {
    private static let browser = "com.example.browser"
    private static let player = "com.example.player"

    @Test func aNewWindowStartsOnAllApps() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = SettingsModel(settings: settings, backlightAvailable: true) { _ in }
        #expect(model.edgeScope == nil)
        #expect(model.edgeScopeChoice == .allApps)
    }

    @Test func addingAnAppSelectsItAndSkipsTrrekAndDuplicates() {
        var received: [AppSettings] = []
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { received.append($0) }

        model.addEdgeProfile(bundleID: Self.browser)
        #expect(model.settings.appEdgeProfiles == [AppEdgeProfile(bundleID: Self.browser)])
        #expect(model.edgeScope == Self.browser)
        #expect(model.edgeScopeChoice == .app(Self.browser))
        #expect(received.count == 1)

        model.edgeScope = nil
        model.addEdgeProfile(bundleID: Self.browser)
        #expect(model.settings.appEdgeProfiles.count == 1)
        #expect(model.edgeScope == Self.browser)
        #expect(received.count == 1)

        model.addEdgeProfile(bundleID: AppIdentity.bundleID)
        model.addEdgeProfile(bundleID: "")
        #expect(model.settings.appEdgeProfiles.count == 1)
        #expect(model.edgeScope == Self.browser)
        #expect(received.count == 1)
    }

    @Test func noAppIsAddedPastTheLimit() {
        var settings = AppSettings()
        settings.appEdgeProfiles = (0 ..< AppSettings.maximumEdgeProfiles).map {
            AppEdgeProfile(bundleID: "com.example.app\($0)")
        }
        let model = SettingsModel(settings: settings, backlightAvailable: true) { _ in }
        #expect(!model.canAddEdgeProfile)
        model.addEdgeProfile(bundleID: Self.browser)
        #expect(model.settings.appEdgeProfiles.count == AppSettings.maximumEdgeProfiles)
        #expect(model.edgeScope == nil)
        // An app already in the list can still be shown.
        model.addEdgeProfile(bundleID: "com.example.app3")
        #expect(model.edgeScope == "com.example.app3")
    }

    @Test func editingAnAppsEdgesLeavesAllAppsAlone() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser), AppEdgeProfile(bundleID: Self.player)]
        let model = SettingsModel(settings: settings, backlightAvailable: true) { _ in }

        model.edgeScope = Self.browser
        #expect(model.edgeOverride(.top) == nil)
        #expect(model.shownEdgeAction(.top) == .switchApps)
        model.setEdgeOverride(.top, to: .switchTabs)
        #expect(model.edgeOverride(.top) == .switchTabs)
        #expect(model.shownEdgeAction(.top) == .switchTabs)
        #expect(model.settings.topEdge == .switchApps)
        #expect(model.settings.edgeProfile(for: Self.player)?.top == nil)

        model.setEdgeOverride(.top, to: nil)
        #expect(model.settings.edgeProfile(for: Self.browser) == AppEdgeProfile(bundleID: Self.browser))

        // All Apps has no overrides to set.
        model.edgeScope = nil
        model.setEdgeOverride(.left, to: .off)
        #expect(model.edgeOverride(.left) == nil)
        #expect(model.settings.appEdgeProfiles.allSatisfy { !$0.hasOverrides })
    }

    @Test func removingAnAppGoesBackToAllApps() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser), AppEdgeProfile(bundleID: Self.player)]
        let model = SettingsModel(settings: settings, backlightAvailable: true) { _ in }
        model.edgeScope = Self.player
        model.removeEdgeProfile()
        #expect(model.settings.appEdgeProfiles == [AppEdgeProfile(bundleID: Self.browser)])
        #expect(model.edgeScope == nil)
    }

    @Test func scopeFollowsAppsRemovedElsewhere() {
        var settings = AppSettings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser)]
        let model = SettingsModel(settings: settings, backlightAvailable: true) { _ in }
        model.edgeScope = Self.browser

        // Kept while the app is still listed.
        var outside = settings
        outside.precision = true
        model.refresh(from: outside)
        #expect(model.edgeScope == Self.browser)

        // An import without it, or Reset to Defaults.
        model.refresh(from: AppSettings())
        #expect(model.edgeScope == nil)
        model.refresh(from: settings)
        model.edgeScope = Self.browser
        model.resetToDefaults()
        #expect(model.settings.appEdgeProfiles.isEmpty)
        #expect(model.edgeScope == nil)
    }

    @Test func inheritedOptionNamesTheAllAppsAction() {
        var settings = AppSettings()
        settings.bottomEdge = .keyboardBacklight
        settings.leftEdge = .zoom
        let withBridge = SettingsModel(settings: settings, backlightAvailable: true) { _ in }
        #expect(withBridge.inheritedEdgeTitle(for: .left) == "Same as All Apps (Zoom)")
        #expect(withBridge.inheritedEdgeTitle(for: .bottom) == "Same as All Apps (Keyboard Backlight)")
        // Without the bridge the keyboard backlight runs, and shows, as media control.
        let noBridge = SettingsModel(settings: settings, backlightAvailable: false) { _ in }
        #expect(noBridge.inheritedEdgeTitle(for: .bottom) == "Same as All Apps (Media)")
    }
}
