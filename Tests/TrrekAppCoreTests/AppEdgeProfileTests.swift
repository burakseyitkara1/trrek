import Foundation
import Testing
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// Edges of their own for apps in front: storage, export, resolution over the All Apps edges and the engine config.
struct AppEdgeProfileTests {
    private static let browser = "com.example.browser"
    private static let player = "com.example.player"

    private static func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    private static func profiles(_ elements: [String]) -> String {
        "{\"schemaVersion\": 1, \"precision\": true, \"appEdgeProfiles\": [\(elements.joined(separator: ", "))]}"
    }

    // MARK: - Storage

    @Test func encodesOnlyTheEdgesAnAppSets() throws {
        var settings = Settings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        let stored = try #require(object["appEdgeProfiles"] as? [[String: Any]])
        #expect(stored.count == 1)
        #expect(stored[0]["bundleID"] as? String == Self.browser)
        #expect(stored[0]["top"] as? String == "switchTabs")
        #expect(stored[0]["left"] == nil)

        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func unreadableProfilesAreDroppedAndUnknownActionsFallBack() throws {
        let settings = try Self.decode(Self.profiles([
            "{\"bundleID\": \"\(Self.browser)\", \"top\": \"teleport\", \"left\": \"volume\", \"extra\": 1}",
            "{\"top\": \"zoom\"}",
            "42",
            "\"text\"",
            "{\"bundleID\": \"\"}",
            "{\"bundleID\": 7}",
            "{\"bundleID\": \"\(Self.player)\", \"bottom\": 3}"
        ]))
        #expect(settings.precision)
        #expect(settings.appEdgeProfiles == [
            AppEdgeProfile(bundleID: Self.browser, left: .volume),
            AppEdgeProfile(bundleID: Self.player)
        ])
    }

    @Test func profilesThatAreNotAListLoadAsNone() throws {
        let settings = try Self.decode("{\"precision\": true, \"appEdgeProfiles\": {\"bundleID\": \"x\"}}")
        #expect(settings.appEdgeProfiles.isEmpty)
        #expect(settings.precision)
    }

    @Test func duplicatesKeepTheFirstAndTrrekIsDropped() throws {
        let settings = try Self.decode(Self.profiles([
            "{\"bundleID\": \"\(AppIdentity.bundleID)\", \"top\": \"zoom\"}",
            "{\"bundleID\": \"\(Self.browser)\", \"top\": \"switchTabs\"}",
            "{\"bundleID\": \"\(Self.player)\"}",
            "{\"bundleID\": \"\(Self.browser)\", \"top\": \"off\"}"
        ]))
        #expect(settings.appEdgeProfiles.map(\.bundleID) == [Self.browser, Self.player])
        #expect(settings.appEdgeProfiles[0].top == .switchTabs)
    }

    @Test func atMostFiftyProfilesAreKept() throws {
        let ids = (0 ..< 60).map { "com.example.app\($0)" }
        let elements = ["{\"bundleID\": \"\(AppIdentity.bundleID)\"}"] + ids.map { "{\"bundleID\": \"\($0)\"}" }
        let settings = try Self.decode(Self.profiles(elements))
        #expect(Settings.maximumEdgeProfiles == 50)
        #expect(settings.appEdgeProfiles.map(\.bundleID) == Array(ids.prefix(50)))
    }

    @Test func resetRemovesEveryProfile() {
        var settings = Settings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]
        #expect(settings.resetToDefaults(backlightAvailable: true).appEdgeProfiles.isEmpty)
    }

    // MARK: - Export and import

    @Test func settingsFileCarriesTheProfiles() throws {
        var settings = Settings()
        settings.appEdgeProfiles = [
            AppEdgeProfile(bundleID: Self.browser, top: .switchTabs),
            AppEdgeProfile(bundleID: Self.player, left: .off, bottom: .scrubVideo)
        ]
        let data = try SettingsDocument.encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = try #require(object["settings"] as? [String: Any])
        #expect((fields["appEdgeProfiles"] as? [Any])?.count == 2)

        let imported = try SettingsDocument.imported(SettingsDocument.decode(data), into: Settings())
        #expect(imported.appEdgeProfiles == settings.appEdgeProfiles)
    }

    @Test func importReadsProfilesForgivingly() throws {
        let json = """
        {"format": "trrek-settings", "formatVersion": 1, "settings": {"appEdgeProfiles": [
          {"bundleID": "\(Self.browser)", "top": "teleport", "right": "zoom"},
          {"bundleID": "\(AppIdentity.bundleID)", "top": "zoom"}
        ]}}
        """
        let decoded = try SettingsDocument.decode(Data(json.utf8))
        #expect(decoded.appEdgeProfiles == [AppEdgeProfile(bundleID: Self.browser, right: .zoom)])
    }

    // MARK: - Resolution

    @Test func edgeActionsResolveTheProfileOverAllApps() {
        var settings = Settings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.player, left: .off, bottom: .scrubVideo)]
        let allApps = EdgeActions(left: .brightness, right: .volume, top: .switchApps, bottom: .keyboardBacklight)

        #expect(settings.edgeActions(for: nil) == allApps)
        #expect(settings.edgeActions(for: "com.example.other") == allApps)
        #expect(settings.edgeActions(for: Self.player)
            == EdgeActions(left: .off, right: .volume, top: .switchApps, bottom: .scrubVideo))

        // An edge left to All Apps follows later changes there.
        settings.rightEdge = .zoom
        #expect(settings.edgeActions(for: Self.player).right == .zoom)
        #expect(settings.edgeActions(for: Self.player)[.left] == .off)
    }

    @Test func profileEditsChangeOnlyThatApp() {
        var settings = Settings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser), AppEdgeProfile(bundleID: Self.player)]
        settings.updateEdgeProfile(for: Self.browser) { $0[edge: .top] = .switchTabs }
        settings.updateEdgeProfile(for: "com.example.missing") { $0[edge: .top] = .zoom }
        #expect(settings.edgeProfile(for: Self.browser)?.top == .switchTabs)
        #expect(settings.edgeProfile(for: Self.player)?.hasOverrides == false)
        #expect(settings.edgeProfile(for: Self.browser)?.hasOverrides == true)
        #expect(settings.appEdgeProfiles.count == 2)
        #expect(settings.edgeProfile(for: nil) == nil)
    }

    // MARK: - Engine config

    @Test func engineConfigUsesTheFrontAppsEdges() {
        var settings = Settings()
        settings.precision = true
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]

        let browser = ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: true,
            frontmostBundleID: Self.browser
        )
        #expect(browser.top == .switchTabs)
        #expect(browser.left == .brightness)
        #expect(browser.precision)

        let other = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, frontmostBundleID: "x.y")
        #expect(other.top == .switchApps)
        #expect(other == ConfigMapper.engineConfig(from: settings, backlightAvailable: true))
    }

    @Test func backlightFallbackAndGatingApplyToTheProfile() {
        var settings = Settings()
        settings.bottomEdge = .volume
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.player, top: .scrubVideo, bottom: .keyboardBacklight)]

        let noBridge = ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: false,
            frontmostBundleID: Self.player
        )
        #expect(noBridge.bottom == .media)

        let untrusted = ConfigMapper.engineConfig(
            from: settings,
            backlightAvailable: true,
            accessibilityTrusted: false,
            frontmostBundleID: Self.player
        )
        #expect(untrusted.top == .off)
        #expect(untrusted.bottom == .keyboardBacklight)
        #expect(untrusted.right == .off)
    }

    @Test func diagramShowsTheScopesEdges() {
        var settings = Settings()
        settings.appEdgeProfiles = [AppEdgeProfile(bundleID: Self.browser, top: .switchTabs)]
        let app = DiagramEdges(
            settings: settings,
            backlightAvailable: true,
            accessibilityTrusted: true,
            bundleID: Self.browser
        )
        #expect(app.top == .switchTabs)
        #expect(DiagramEdges(settings: settings, backlightAvailable: true, accessibilityTrusted: true).top
            == .switchApps)
    }

    // MARK: - Status menu

    @Test func statusLineNamesTheAppWhileItsEdgesApply() {
        var settings = Settings()
        settings.appEdgeProfiles = [
            AppEdgeProfile(bundleID: Self.browser, top: .switchTabs),
            AppEdgeProfile(bundleID: Self.player)
        ]
        #expect(StatusText.edgeProfileLine(bundleID: Self.browser, appName: "Browser", settings: settings)
            == "Edges set for Browser")
        // No profile, a profile that sets nothing, or no front app: All Apps applies.
        #expect(StatusText.edgeProfileLine(bundleID: "x.y", appName: "Other", settings: settings) == nil)
        #expect(StatusText.edgeProfileLine(bundleID: Self.player, appName: "Player", settings: settings) == nil)
        #expect(StatusText.edgeProfileLine(bundleID: nil, appName: "None", settings: settings) == nil)
        // Pausing wins.
        settings.pausedBundleIDs = [Self.browser]
        #expect(StatusText.edgeProfileLine(bundleID: Self.browser, appName: "Browser", settings: settings) == nil)
    }
}
