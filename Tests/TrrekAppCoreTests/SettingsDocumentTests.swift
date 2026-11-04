import Foundation
import Testing
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

struct SettingsDocumentTests {
    /// Every field changed from its default.
    private static var customized: Settings {
        var settings = Settings()
        settings.hapticStrength = .strong
        settings.edgeWidth = .wide
        settings.precision = true
        settings.freezeCursor = false
        settings.bottomQuarterOnly = true
        settings.slideSensitivity = .veryLow
        settings.externalMonitorBrightness = true
        settings.leftEdge = .volume
        settings.rightEdge = .switchTabs
        settings.topEdge = .media
        settings.bottomEdge = .scrubVideo
        settings.topLeft = .missionControl
        settings.topRight = .screenshot
        settings.bottomLeft = .lockScreen
        settings.bottomRight = .mute
        settings.middleClick = true
        settings.holdKey = .option
        settings.holdKeyMode = .toggle
        settings.pausedBundleIDs = ["com.example.one", "com.example/two"]
        settings.launchAtLogin = false
        settings.welcomeShown = true
        settings.language = .turkish
        return settings
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func roundTripKeepsEverythingButLocalFields() throws {
        let original = Self.customized
        let decoded = try SettingsDocument.decode(SettingsDocument.encode(original))

        var expected = original
        expected.launchAtLogin = Settings().launchAtLogin
        expected.welcomeShown = Settings().welcomeShown
        expected.language = Settings().language
        #expect(decoded == expected)
    }

    @Test func importKeepsCurrentLocalFields() throws {
        let decoded = try SettingsDocument.decode(SettingsDocument.encode(Self.customized))
        var current = Settings()
        current.launchAtLogin = false
        current.welcomeShown = true
        current.language = .turkish

        let applied = SettingsDocument.imported(decoded, into: current)

        #expect(applied == Self.customized)
        #expect(!applied.launchAtLogin)
        #expect(applied.welcomeShown)
        #expect(applied.language == .turkish)

        // The language is this user's: importing never changes it.
        current.language = .english
        #expect(SettingsDocument.imported(decoded, into: current).language == .english)
    }

    @Test func fileHasHeaderSortedKeysAndNoLocalFields() throws {
        let data = try SettingsDocument.encode(Self.customized)
        let object = try Self.object(data)

        #expect(object["format"] as? String == "trrek-settings")
        #expect(object["formatVersion"] as? Int == 1)
        #expect(object["appVersion"] as? String == TrrekVersion.string)
        let settings = try #require(object["settings"] as? [String: Any])
        #expect(settings["launchAtLogin"] == nil)
        #expect(settings["welcomeShown"] == nil)
        #expect(settings["topEdge"] as? String == "media")
        #expect(settings["language"] == nil)

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n  \"appVersion\""))
        let keys = ["\"appVersion\"", "\"format\"", "\"formatVersion\"", "\"settings\""]
        let positions = try keys.map { try #require(text.range(of: $0)).lowerBound }
        #expect(positions == positions.sorted())
        #expect(text.contains("com.example/two"))
    }

    @Test func emptyDataIsNotASettingsFile() {
        #expect(throws: SettingsDocumentError.notSettingsFile) {
            try SettingsDocument.decode(Data())
        }
    }

    @Test(arguments: [
        "not json",
        "{\"format\": \"trrek-sett",
        "[1, 2, 3]",
        "\"trrek-settings\"",
        "{}",
        "{\"format\": \"other\", \"formatVersion\": 1, \"settings\": {}}",
        "{\"formatVersion\": 1, \"settings\": {}}",
        "{\"format\": \"trrek-settings\", \"settings\": {}}",
        "{\"format\": \"trrek-settings\", \"formatVersion\": \"1\", \"settings\": {}}",
        "{\"format\": \"trrek-settings\", \"formatVersion\": 0, \"settings\": {}}",
        "{\"format\": \"trrek-settings\", \"formatVersion\": -1, \"settings\": {}}",
        "{\"format\": \"trrek-settings\", \"formatVersion\": 1}",
        "{\"format\": \"trrek-settings\", \"formatVersion\": 1, \"settings\": [1]}"
    ])
    func malformedDataIsNotASettingsFile(json: String) {
        #expect(throws: SettingsDocumentError.notSettingsFile) {
            try SettingsDocument.decode(Self.data(json))
        }
    }

    @Test func newerFormatVersionIsRefused() {
        let json = "{\"format\": \"trrek-settings\", \"formatVersion\": 2, \"settings\": {}}"
        #expect(throws: SettingsDocumentError.newerFormat) {
            try SettingsDocument.decode(Self.data(json))
        }
    }

    @Test func newerSettingsSchemaIsRefused() {
        let json = """
        {"format": "trrek-settings", "formatVersion": 1, "settings": {"schemaVersion": 99, "precision": true}}
        """
        #expect(throws: SettingsDocumentError.newerFormat) {
            try SettingsDocument.decode(Self.data(json))
        }
    }

    @Test func unknownValuesFallBackToDefaults() throws {
        let json = """
        {
          "format": "trrek-settings",
          "formatVersion": 1,
          "appVersion": "9.9.9",
          "futureField": true,
          "settings": {
            "topEdge": "teleport",
            "bottomEdge": "media",
            "topLeft": 42,
            "precision": true,
            "somethingNew": "value"
          }
        }
        """
        let decoded = try SettingsDocument.decode(Self.data(json))

        #expect(decoded.topEdge == Settings().topEdge)
        #expect(decoded.topLeft == Settings().topLeft)
        #expect(decoded.bottomEdge == .media)
        #expect(decoded.precision)
    }

    @Test func localFieldsInTheFileAreIgnored() throws {
        let json = """
        {"format": "trrek-settings", "formatVersion": 1, "settings": {"launchAtLogin": false, "welcomeShown": true}}
        """
        let decoded = try SettingsDocument.decode(Self.data(json))
        var current = Settings()
        current.launchAtLogin = true
        current.welcomeShown = false

        let applied = SettingsDocument.imported(decoded, into: current)

        #expect(applied.launchAtLogin)
        #expect(!applied.welcomeShown)
    }

    @Test func fileNameAndExtension() {
        #expect(SettingsDocument.defaultFileName == "trrek Settings.trrek")
        #expect(URL(fileURLWithPath: SettingsDocument.defaultFileName).pathExtension == SettingsDocument.fileExtension)
        #expect(SettingsDocument.isSettingsFile(URL(fileURLWithPath: "/tmp/Mine.trrek")))
        #expect(SettingsDocument.isSettingsFile(URL(fileURLWithPath: "/tmp/Mine.TRREK")))
        #expect(!SettingsDocument.isSettingsFile(URL(fileURLWithPath: "/tmp/Mine.json")))
        #expect(!SettingsDocument.isSettingsFile(URL(fileURLWithPath: "/tmp/trrek")))
    }

    @Test func readRefusesLargeFilesAndDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let small = directory.appendingPathComponent("Small.trrek")
        let contents = try SettingsDocument.encode(Self.customized)
        try contents.write(to: small)
        #expect(try SettingsDocument.read(contentsOf: small) == contents)

        let large = directory.appendingPathComponent("Large.trrek")
        try Data(count: SettingsDocument.maximumFileSize + 1).write(to: large)
        #expect(throws: SettingsDocumentError.notSettingsFile) {
            try SettingsDocument.read(contentsOf: large)
        }

        let folder = directory.appendingPathComponent("Folder.trrek")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: SettingsDocumentError.notSettingsFile) {
            try SettingsDocument.read(contentsOf: folder)
        }

        #expect(throws: (any Error).self) {
            try SettingsDocument.read(contentsOf: directory.appendingPathComponent("Missing.trrek"))
        }
    }

    @Test func errorsExplainThatNothingChanged() {
        #expect(SettingsDocumentError.notSettingsFile.message.contains("not changed"))
        #expect(SettingsDocumentError.newerFormat.message.contains("newer version"))
    }
}
