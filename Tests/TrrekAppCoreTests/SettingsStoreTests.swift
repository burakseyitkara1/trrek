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
        settings.slideSensitivity = .veryHigh
        settings.externalMonitorBrightness = true
        settings.leftEdge = .zoom
        settings.rightEdge = .switchDesktops
        settings.topEdge = .switchTabs
        settings.bottomEdge = .undoRedo
        settings.topLeft = .missionControl
        settings.topRight = .appWindows
        settings.bottomLeft = .lockScreen
        settings.bottomRight = .screenshotArea
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

    @Test func decodesOlderSettingsBlobKeepingKnownFields() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        // An older blob: an earlier schema version and only some of today's fields.
        let json = """
        {"schemaVersion": 0, "precision": true, "topEdge": "media", "pausedBundleIDs": ["com.example.one"]}
        """
        defaults.set(Data(json.utf8), forKey: "settings")
        let loaded = SettingsStore(defaults: defaults).load()

        var expected = Settings()
        expected.precision = true
        expected.topEdge = .media
        expected.pausedBundleIDs = ["com.example.one"]
        #expect(loaded == expected)
        #expect(loaded.schemaVersion == Settings.currentSchemaVersion)
    }

    @Test func blobWithoutSchemaVersionKeepsKnownFields() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        defaults.set(Data(#"{"precision": true}"#.utf8), forKey: "settings")
        let loaded = SettingsStore(defaults: defaults).load()
        #expect(loaded.precision)
        #expect(loaded.schemaVersion == Settings.currentSchemaVersion)
    }

    @Test func swapSidesMigratesToSideEdgeActions() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        // Settings from 0.2: Swap Sides on.
        defaults.set(Data(#"{"schemaVersion": 1, "swapSides": true, "precision": true}"#.utf8), forKey: "settings")
        let swapped = SettingsStore(defaults: defaults).load()
        #expect(swapped.leftEdge == .volume)
        #expect(swapped.rightEdge == .brightness)
        #expect(swapped.precision)

        defaults.set(Data(#"{"schemaVersion": 1, "swapSides": false}"#.utf8), forKey: "settings")
        let unswapped = SettingsStore(defaults: defaults).load()
        #expect(unswapped.leftEdge == .brightness)
        #expect(unswapped.rightEdge == .volume)

        // Saving writes the side edges and no longer writes `swapSides`.
        SettingsStore(defaults: defaults).save(swapped)
        let data = try #require(defaults.data(forKey: "settings"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["swapSides"] == nil)
        #expect(object["leftEdge"] as? String == "volume")
        #expect(object["rightEdge"] as? String == "brightness")
        #expect(SettingsStore(defaults: defaults).load() == swapped)
    }

    @Test func storedSideEdgesWinOverSwapSides() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        let json = #"{"schemaVersion": 1, "swapSides": true, "leftEdge": "zoom", "rightEdge": "undoRedo"}"#
        defaults.set(Data(json.utf8), forKey: "settings")
        let loaded = SettingsStore(defaults: defaults).load()
        #expect(loaded.leftEdge == .zoom)
        #expect(loaded.rightEdge == .undoRedo)

        // An unreadable side edge falls back to what Swap Sides meant, the other keeps its stored value.
        let partial = #"{"swapSides": true, "leftEdge": "teleport", "rightEdge": "media"}"#
        defaults.set(Data(partial.utf8), forKey: "settings")
        let mixed = SettingsStore(defaults: defaults).load()
        #expect(mixed.leftEdge == .volume)
        #expect(mixed.rightEdge == .media)
    }

    @Test func newerSchemaFallsBackToDefaults() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        let json = """
        {"schemaVersion": \(Settings.currentSchemaVersion + 1), "precision": true, "edgeWidth": "wide"}
        """
        defaults.set(Data(json.utf8), forKey: "settings")
        #expect(SettingsStore(defaults: defaults).load() == Settings())
    }

    @Test func unknownEnumValueFallsBackPerField() throws {
        let defaults = try Self.freshDefaults()
        defer { Self.wipe(defaults) }

        let json = """
        {"schemaVersion": 1, "hapticStrength": "thunderous", "edgeWidth": "wide", "topEdge": "teleport",
         "bottomEdge": "media", "topLeft": "confetti", "topRight": "mute", "holdKey": "hyper", "precision": "yes"}
        """
        defaults.set(Data(json.utf8), forKey: "settings")
        let loaded = SettingsStore(defaults: defaults).load()

        var expected = Settings()
        expected.edgeWidth = .wide
        expected.bottomEdge = .media
        expected.topRight = .mute
        #expect(loaded == expected)
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
        #expect(settings.slideSensitivity == .standard)
        #expect(!settings.externalMonitorBrightness)
        #expect(settings.leftEdge == .brightness)
        #expect(settings.rightEdge == .volume)
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
