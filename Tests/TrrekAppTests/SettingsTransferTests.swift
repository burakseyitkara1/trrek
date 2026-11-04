import Foundation
import Testing
@testable import Trrek
import TrrekAppCore
import TrrekEngine
import UniformTypeIdentifiers

/// Exporting and importing through the settings window's model, with files in a temporary directory.
@MainActor
struct SettingsTransferTests {
    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeSettingsFile(named name: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(name)
        var exported = AppSettings()
        exported.precision = true
        exported.topEdge = .media
        try SettingsDocument.encode(exported).write(to: file)
        return file
    }

    @Test func exportThenImportReplacesSettingsThroughOnChange() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(SettingsDocument.defaultFileName)

        var exported = AppSettings()
        exported.precision = true
        exported.topEdge = .media
        exported.pausedBundleIDs = ["com.example.app"]
        exported.launchAtLogin = false
        exported.welcomeShown = false
        SettingsModel(settings: exported, backlightAvailable: true) { _ in }.exportSettings(to: file)

        var current = AppSettings()
        current.launchAtLogin = true
        current.welcomeShown = true
        var received: [AppSettings] = []
        let model = SettingsModel(settings: current, backlightAvailable: true) { received.append($0) }

        await model.prepareImport(from: file)
        #expect(model.isConfirmingImport)
        #expect(!model.isReadingImport)
        let pending = try #require(model.pendingImport)
        #expect(pending.fileName == "trrek Settings.trrek")
        #expect(received.isEmpty)

        model.confirmImport(pending)
        #expect(!model.isConfirmingImport)
        #expect(received.count == 1)
        #expect(model.settings.precision)
        #expect(model.settings.topEdge == .media)
        #expect(model.settings.pausedBundleIDs == ["com.example.app"])
        #expect(model.settings.launchAtLogin)
        #expect(model.settings.welcomeShown)
    }

    /// The alert may clear its binding (and, before, the pending value) before Replace's action runs.
    @Test func replaceAppliesTheCapturedImportWhenThePendingValueWasClearedFirst() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try Self.writeSettingsFile(named: "Other.trrek", in: directory)
        var received: [AppSettings] = []
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { received.append($0) }

        await model.prepareImport(from: file)
        let captured = try #require(model.pendingImport)
        model.isConfirmingImport = false
        model.pendingImport = nil
        model.confirmImport(captured)

        #expect(received.count == 1)
        #expect(model.settings.precision)
        #expect(model.settings.topEdge == .media)
    }

    @Test func cancellingLeavesSettingsAlone() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try Self.writeSettingsFile(named: "Other.trrek", in: directory)
        var calls = 0
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in calls += 1 }

        await model.prepareImport(from: file)
        model.isConfirmingImport = false

        #expect(calls == 0)
        #expect(model.settings == AppSettings())
        // The title keeps the file name while the alert animates out.
        #expect(SettingsTransferAlerts.importTitle(model.pendingImport).contains("“Other.trrek”"))
        #expect(!SettingsTransferAlerts.importTitle(nil).isEmpty)
    }

    @Test func invalidFileShowsFailureAndChangesNothing() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Broken.trrek")
        try Data("{\"format\": \"something-else\"}".utf8).write(to: file)

        var calls = 0
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in calls += 1 }
        await model.prepareImport(from: file)

        #expect(!model.isConfirmingImport)
        #expect(model.isShowingTransferFailure)
        #expect(model.transferFailure?.title == "“Broken.trrek” could not be imported.")
        #expect(model.transferFailure?.message == SettingsDocumentError.notSettingsFile.message)
        #expect(calls == 0)

        model.isShowingTransferFailure = false
        // Kept so the closing alert keeps its text.
        #expect(model.transferFailure != nil)
    }

    @Test func tooLargeFileIsRefused() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Huge.trrek")
        try Data(count: SettingsDocument.maximumFileSize + 1).write(to: file)
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }

        await model.prepareImport(from: file)

        #expect(model.transferFailure?.message == SettingsDocumentError.notSettingsFile.message)
    }

    @Test func missingFileShowsFailure() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }

        await model.prepareImport(from: directory.appendingPathComponent("Missing.trrek"))

        #expect(model.isShowingTransferFailure)
        #expect(model.transferFailure?.message.contains("could not be read") == true)
    }

    /// A file opened from Finder while a confirmation is showing does not replace the import the alert names.
    @Test func openedFileIsIgnoredWhileAnAlertIsShowing() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try Self.writeSettingsFile(named: "First.trrek", in: directory)
        let second = try Self.writeSettingsFile(named: "Second.trrek", in: directory)
        let broken = directory.appendingPathComponent("Broken.trrek")
        try Data("x".utf8).write(to: broken)
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }

        await model.openedFile(at: first)
        await model.openedFile(at: second)
        await model.openedFile(at: broken)

        #expect(model.pendingImport?.fileName == "First.trrek")
        #expect(model.isConfirmingImport)
        #expect(!model.isShowingTransferFailure)

        model.isConfirmingImport = false
        model.confirmingReset = true
        await model.openedFile(at: second)
        #expect(model.pendingImport?.fileName == "First.trrek")
        #expect(!model.isConfirmingImport)

        model.confirmingReset = false
        await model.openedFile(at: second)
        #expect(model.pendingImport?.fileName == "Second.trrek")
        #expect(model.isConfirmingImport)
    }

    @Test func exportFailureShowsAlert() {
        let model = SettingsModel(settings: AppSettings(), backlightAvailable: true) { _ in }
        model.exportSettings(to: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/x.trrek"))
        #expect(model.isShowingTransferFailure)
        #expect(model.transferFailure?.title == "The settings could not be exported.")
    }

    /// The type the panels and `application(_:open:)` rely on is the one the bundle declares.
    @Test func infoPlistDeclaresTheSettingsType() throws {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist.in")
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: template), format: nil) as? [String: Any]
        )
        let exported = try #require(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let type = try #require(exported.first { $0["UTTypeIdentifier"] as? String == SettingsDocument.typeIdentifier })
        #expect(type["UTTypeConformsTo"] as? [String] == ["public.json"])
        let tags = try #require(type["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == [SettingsDocument.fileExtension])

        let documents = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let document = try #require(documents.first)
        #expect(document["CFBundleTypeRole"] as? String == "Viewer")
        #expect(document["LSItemContentTypes"] as? [String] == [SettingsDocument.typeIdentifier])
        #expect(UTType.trrekSettings.identifier == SettingsDocument.typeIdentifier)
    }
}
