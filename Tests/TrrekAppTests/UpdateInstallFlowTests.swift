import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// The in-place install after a download, with a fake installer and relaunch: which alerts show, what is opened and
/// when trrek relaunches.
@MainActor
@Suite(.serialized)
struct UpdateInstallFlowTests {
    private typealias Harness = UpdateControllerTests.Harness

    private static func harness(
        _ installer: UpdateControllerTests.Installer,
        relaunchSucceeds: Bool = true
    ) throws -> Harness {
        try UpdateControllerTests.harness(
            installer: installer,
            relaunchSucceeds: relaunchSucceeds,
            suite: "trrek.tests.update-install"
        )
    }

    private static func image(_ harness: Harness) -> URL {
        harness.folder.appendingPathComponent("trrek-v0.4.0.dmg")
    }

    @Test func aVerifiedUpdateIsInstalledAndRelaunches() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        var installing: [SemanticVersion?] = []
        harness.controller.onChange = { installing.append(harness.controller.installingVersion) }

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        #expect(try harness.alerts.shown == [
            .available(release, current: #require(SemanticVersion("0.3.0"))),
            .readyToInstall(release)
        ])
        #expect(installer.calls == ["prepare trrek-v0.4.0.dmg as 0.4.0 over 0.3.0", "install"])
        #expect(harness.relaunches() == 1)
        #expect(harness.opened().isEmpty)
        #expect(installing.contains(SemanticVersion("0.4.0")))
        // trrek quits now; until it does, nothing else starts.
        #expect(harness.controller.isBusy)
    }

    @Test func laterKeepsTheDiskImageForTheMenu() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        harness.alerts.installAnswer = false

        await harness.controller.checkManually()

        #expect(installer.calls.last == "discard")
        #expect(harness.controller.pendingInstall?.release.version == SemanticVersion("0.4.0"))
        #expect(harness.controller.pendingInstall?.image.file == Self.image(harness))
        #expect(harness.controller.installingVersion == nil)
        #expect(!harness.controller.isBusy)
        #expect(harness.relaunches() == 0)
        #expect(harness.opened().isEmpty)

        // "Install trrek 0.4.0…" verifies again and installs.
        harness.alerts.installAnswer = true
        await harness.controller.installPending()
        #expect(installer.calls.suffix(2) == ["prepare trrek-v0.4.0.dmg as 0.4.0 over 0.3.0", "install"])
        #expect(installer.calls.count(where: { $0.hasPrefix("prepare") }) == 2)
        #expect(harness.controller.pendingInstall == nil)
        #expect(harness.relaunches() == 1)
    }

    /// A kept disk image that was deleted meanwhile is downloaded again.
    @Test func aMissingKeptImageIsDownloadedAgain() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        harness.alerts.installAnswer = false
        await harness.controller.checkManually()
        try FileManager.default.removeItem(at: Self.image(harness))

        harness.alerts.installAnswer = true
        await harness.controller.installPending()

        #expect(FileManager.default.fileExists(atPath: Self.image(harness).path))
        #expect(installer.calls.last == "install")
        #expect(harness.relaunches() == 1)
    }

    /// A click on the notification while an update is kept installs it.
    @Test func aNotificationClickInstallsAKeptUpdate() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        harness.alerts.installAnswer = false
        await harness.controller.checkManually()
        harness.alerts.installAnswer = true

        await harness.controller.notificationOpened(version: "0.4.0")

        #expect(installer.calls.last == "install")
        #expect(harness.relaunches() == 1)
    }

    @Test func aLocationTrrekCannotReplaceOpensTheDiskImage() async throws {
        for error in [UpdateInstallError.location(.notWritable), .location(.translocated), .extraction] {
            let installer = UpdateControllerTests.Installer()
            installer.prepareError = error
            let harness = try Self.harness(installer)
            defer { harness.tearDown() }

            await harness.controller.checkManually()

            let release = try #require(harness.controller.availableUpdate)
            #expect(harness.alerts.shown.last == .installFallback(release, message: error.message))
            #expect(harness.opened() == [Self.image(harness)])
            #expect(installer.calls.count == 1)
            #expect(harness.relaunches() == 0)
            #expect(!harness.controller.isBusy)
        }
    }

    @Test func aFailedReplaceOpensTheDiskImage() async throws {
        let installer = UpdateControllerTests.Installer()
        installer.installError = .replacement
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        #expect(harness.alerts.shown.last == .installFallback(release, message: UpdateInstallError.replacement.message))
        #expect(harness.opened() == [Self.image(harness)])
        #expect(harness.relaunches() == 0)
        #expect(harness.controller.pendingInstall == nil)
    }

    /// A refused update is not opened; the alert offers the release page and the disk image stays in Downloads.
    @Test func aFailedVerificationShowsAnErrorAndKeepsTheImage() async throws {
        let installer = UpdateControllerTests.Installer()
        installer.prepareError = .verification(.notNotarized)
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        let message = UpdateVerificationFailure.notNotarized.message
        #expect(harness.alerts.shown.last == .verificationFailed(release, message: message))
        #expect(harness.opened() == [release.pageURL])
        #expect(FileManager.default.fileExists(atPath: Self.image(harness).path))
        #expect(harness.relaunches() == 0)
        #expect(!harness.controller.isBusy)

        harness.alerts.answer = false
        await harness.controller.download()
        #expect(harness.opened() == [release.pageURL])
    }

    @Test func aFailedRelaunchSaysToReopen() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer, relaunchSucceeds: false)
        defer { harness.tearDown() }

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        #expect(harness.alerts.shown.last == .relaunchNeeded(release))
        #expect(harness.relaunches() == 1)
        #expect(!harness.controller.isBusy)
    }

    @Test func theMenuFollowsThePhases() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        var phases: [InstallPhase] = []
        harness.controller.onChange = {
            if let phase = harness.controller.installPhase, phases.last != phase {
                phases.append(phase)
            }
        }
        await harness.controller.checkManually()
        #expect(phases == [.verifying, .ready, .installing])
    }

    /// A second request while an install is being prepared (a menu choice, a notification click, a download) does
    /// nothing.
    @Test func aSecondRequestDuringAnInstallIsIgnored() async throws {
        let installer = UpdateControllerTests.Installer()
        installer.prepareDelay = .milliseconds(300)
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        let first = Task { await harness.controller.checkManually() }
        try await waitUntil { harness.controller.installPhase == .verifying }
        let release = try #require(harness.controller.availableUpdate)
        let image = DownloadedDiskImage(file: Self.image(harness), isQuarantined: true)

        await harness.controller.installOrOpen(image, release: release)
        await harness.controller.download()
        await harness.controller.notificationOpened(version: "0.4.0")
        await harness.controller.checkManually()
        await first.value

        #expect(installer.calls.count(where: { $0.hasPrefix("prepare") }) == 1)
        #expect(harness.relaunches() == 1)
    }

    /// Quitting while "ready to install" is shown removes the staged app.
    @Test func quittingDuringTheAlertDiscardsTheStagedApp() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer)
        defer { harness.tearDown() }
        let staging = harness.folder.appendingPathComponent("staging")
        var existedDuringAlert = false
        harness.alerts.onPresent = { alert in
            guard case .readyToInstall = alert else { return }
            existedDuringAlert = FileManager.default.fileExists(atPath: staging.path)
            harness.controller.discardStagedUpdate()
        }
        harness.alerts.installAnswer = false
        await harness.controller.checkManually()
        #expect(existedDuringAlert)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    /// After an install whose relaunch failed, the installed release is not offered again.
    @Test func anInstalledUpdateIsNotOfferedAgain() async throws {
        let installer = UpdateControllerTests.Installer()
        let harness = try Self.harness(installer, relaunchSucceeds: false)
        defer { harness.tearDown() }
        await harness.controller.checkManually()
        let release = try #require(harness.controller.availableUpdate)
        #expect(harness.controller.installedVersion == release.version)

        await harness.controller.download()
        await harness.controller.notificationOpened(version: "0.4.0")
        #expect(installer.calls.count(where: { $0.hasPrefix("prepare") }) == 1)
        #expect(harness.alerts.shown.suffix(2) == [.relaunchNeeded(release), .relaunchNeeded(release)])
    }

    @Test func installAlertsHaveTheirButtons() throws {
        let release = try ReleaseInfo.decode(UpdateControllerTests.releaseJSON("0.4.0"))
        let ready = SystemUpdateAlerts.makeAlert(.readyToInstall(release))
        #expect(ready.messageText == "trrek 0.4.0 is ready to install")
        #expect(ready.buttons.map(\.title) == ["Install and Relaunch", "Later"])

        let fallback = SystemUpdateAlerts.makeAlert(.installFallback(release, message: "Reason."))
        #expect(fallback.messageText == "trrek 0.4.0 couldn’t be installed automatically")
        #expect(fallback.informativeText.hasPrefix("Reason.\n\n"))
        #expect(fallback.buttons.map(\.title) == ["OK"])

        let refused = SystemUpdateAlerts.makeAlert(.verificationFailed(release, message: "Bad."))
        #expect(refused.messageText == "trrek 0.4.0 couldn’t be verified")
        #expect(refused.informativeText.hasPrefix("Bad.\n\n"))
        #expect(refused.buttons.map(\.title) == ["Open Download Page", "Cancel"])

        let installed = SystemUpdateAlerts.makeAlert(.relaunchNeeded(release))
        #expect(installed.messageText == "trrek 0.4.0 is installed")
        #expect(installed.buttons.map(\.title) == ["OK"])
    }
}

extension UpdateControllerTests {
    /// Records the install steps; each fails with its configured error.
    final class Installer: UpdateInstalling, @unchecked Sendable {
        var prepareError: UpdateInstallError?
        var installError: UpdateInstallError?
        /// How long `prepare` takes, so a second request can arrive meanwhile.
        var prepareDelay: Duration = .zero
        private(set) var calls: [String] = []

        func prepare(
            image: URL,
            version: SemanticVersion,
            current: SemanticVersion
        ) async throws(UpdateInstallError) -> StagedUpdate {
            calls.append("prepare \(image.lastPathComponent) as \(version) over \(current)")
            try? await Task.sleep(for: prepareDelay)
            if let prepareError {
                throw prepareError
            }
            let folder = image.deletingLastPathComponent().appendingPathComponent("staging")
            let app = folder.appendingPathComponent("trrek.app")
            try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            return StagedUpdate(app: app, folder: folder, version: version, current: current)
        }

        func install(_: StagedUpdate) async throws(UpdateInstallError) {
            calls.append("install")
            if let installError {
                throw installError
            }
        }

        func discard(_: StagedUpdate) async {
            calls.append("discard")
        }

        func cleanUpLeftovers() async {
            calls.append("clean up")
        }
    }
}
