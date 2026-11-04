import Foundation
import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine

/// The settings window's model → store path. Uses its own defaults suite, wiped before and after.
@MainActor
@Suite(.serialized)
struct SettingsModelTests {
    private static let suiteName = "trrek.tests.settings-model"

    private static func freshStore() throws -> (SettingsStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test func changesAreStoredAndSurviveReload() throws {
        let (store, defaults) = try Self.freshStore()
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        var received: [AppSettings] = []
        let model = SettingsModel(settings: store.load(), backlightAvailable: true) { settings in
            received.append(settings)
            store.save(settings)
        }

        model.settings.precision = true
        model.settings[corner: .topRight] = .screenshot
        model.settings.pausedBundleIDs.append("com.example.app")

        #expect(received.count == 3)
        let reloaded = SettingsStore(defaults: defaults).load()
        #expect(reloaded.precision)
        #expect(reloaded.topRight == .screenshot)
        #expect(reloaded.pausedBundleIDs == ["com.example.app"])
        #expect(reloaded == model.settings)
    }

    @Test func unchangedValuesAreNotPassedOn() {
        var calls = 0
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in calls += 1 }
        model.settings.freezeCursor = true
        model.settings = AppSettings()
        #expect(calls == 0)
    }

    @Test func refreshShowsOutsideChangesWithoutPassingThemOn() {
        var calls = 0
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in calls += 1 }
        var outside = AppSettings()
        outside.swapSides = true
        model.refresh(from: outside)
        #expect(model.settings.swapSides)
        #expect(calls == 0)
        model.settings.swapSides = false
        #expect(calls == 1)
    }

    @Test func resetKeepsLaunchState() {
        var initial = AppSettings()
        initial.launchAtLogin = false
        initial.welcomeShown = true
        initial.middleClick = true
        var last: AppSettings?
        let model = SettingsModel(settings: initial, backlightAvailable: false) { last = $0 }

        model.resetToDefaults()

        #expect(last?.middleClick == false)
        #expect(last?.launchAtLogin == false)
        #expect(last?.welcomeShown == true)
        #expect(last?.bottomEdge == .media)
    }
}
