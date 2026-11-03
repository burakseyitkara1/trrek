import Foundation
import Testing
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// All tests share one defaults suite, so they run one at a time and wipe it before and after.
@Suite(.serialized)
struct SettingsStoreTests {
    private static let suiteName = "trrek.tests"

    private static func freshDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func wipe(_ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func roundTripPreservesAllFields() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        var settings = Settings()
        settings.hapticStrength = .strong
        settings.edgeWidth = .wide
        settings.precision = true
        settings.freezeCursor = false
        settings.bottomQuarterOnly = true
        settings.swapSides = true
        settings.externalMonitorBrightness = true
        settings.topEdge = .media
        settings.bottomEdge = .scrubVideo
        settings.topLeft = .mute
        settings.topRight = .screenshot
        settings.bottomLeft = .screenshot
        settings.bottomRight = .mute
        settings.middleClick = true
        settings.holdKey = .option
        settings.holdKeyMode = .toggle
        settings.pausedBundleIDs = ["com.example.one", "com.example.two"]
        settings.launchAtLogin = false
        settings.welcomeShown = true
        #expect(settings != Settings())

        SettingsStore(defaults: defaults).save(settings)
        let loaded = SettingsStore(defaults: defaults).load()

        #expect(loaded == settings)
        #expect(loaded.schemaVersion == Settings.currentSchemaVersion)
        #expect(defaults.data(forKey: "settings") != nil)
    }

    @Test func storeFallsBackToDefaultsOnCorruptData() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        defaults.set(Data("x".utf8), forKey: "settings")
        #expect(SettingsStore(defaults: defaults).load() == Settings())
    }

    @Test func storeFallsBackOnSchemaMismatch() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        var settings = Settings()
        settings.precision = true
        settings.schemaVersion = Settings.currentSchemaVersion + 1
        SettingsStore(defaults: defaults).save(settings)

        let loaded = SettingsStore(defaults: defaults).load()
        #expect(loaded == Settings())
        #expect(!loaded.precision)
    }

    @Test func missingDataLoadsDefaults() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        #expect(SettingsStore(defaults: defaults).load() == Settings())
    }

    @Test func defaultsMatchSpec() {
        let settings = Settings()
        #expect(settings.schemaVersion == 1)
        #expect(settings.hapticStrength == .medium)
        #expect(settings.edgeWidth == .standard)
        #expect(!settings.precision)
        #expect(settings.freezeCursor)
        #expect(!settings.bottomQuarterOnly)
        #expect(!settings.swapSides)
        #expect(!settings.externalMonitorBrightness)
        #expect(settings.topEdge == .switchApps)
        #expect(settings.bottomEdge == .keyboardBacklight)
        let corners = [settings.topLeft, settings.topRight, settings.bottomLeft, settings.bottomRight]
        #expect(corners == Array(repeating: .off, count: 4))
        #expect(!settings.middleClick)
        #expect(settings.holdKey == HoldKey.none)
        #expect(settings.holdKeyMode == .hold)
        #expect(settings.pausedBundleIDs.isEmpty)
        #expect(settings.launchAtLogin)
        #expect(!settings.welcomeShown)
    }
}
