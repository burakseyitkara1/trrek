import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// The update the menu row starts, with a fake downloader, installer and relaunch: the row's states, what is opened
/// and when trrek relaunches. No alert is ever shown.
@MainActor
@Suite(.serialized)
struct UpdateInstallFlowTests {
    private typealias Harness = UpdateControllerTests.Harness
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    /// A harness whose check already found 0.4.0.
    private static func harness(
        downloader: UpdateControllerTests.Downloader = .init(fails: false),
        relaunchSucceeds: Bool = true
    ) async throws -> Harness {
        let harness = try UpdateControllerTests.harness(
            downloader: downloader,
            relaunchSucceeds: relaunchSucceeds,
            suite: "trrek.tests.update-install"
        )
        await harness.controller.checkManually()
        #expect(harness.controller.row == .available(version))
        return harness
    }

    private static func cachedFiles(_ harness: Harness) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: harness.cache.path)) ?? []
    }

    @Test func theRowDownloadsWithProgressInstallsAndRelaunches() async throws {
        let harness = try await Self.harness()
        defer { harness.tearDown() }

        harness.controller.startUpdate()
        #expect(harness.controller.isBusy)
        try await waitUntil { harness.relaunches() == 1 }

        let ver = Self.version
        #expect(harness.rows().suffix(4) == [
            .downloading(ver, progress: nil), .downloading(ver, progress: 0.5), .downloading(ver, progress: 1),
            .installing(ver)
        ])
        #expect(harness.installer.calls == ["prepare trrek-v0.4.0.dmg as 0.4.0 over 0.3.0", "install"])
        #expect(harness.opened().isEmpty)
        #expect(harness.alerts.shown.isEmpty)
        // The disk image is deleted once installed.
        #expect(Self.cachedFiles(harness).isEmpty)
    }

    @Test func aFailedDownloadOffersToTryAgain() async throws {
        let harness = try await Self.harness(downloader: .init(fails: true))
        defer { harness.tearDown() }
        harness.controller.startUpdate()
        try await waitUntil { harness.controller.row == .failed(Self.version) }
        #expect(!harness.controller.isBusy)
        #expect(harness.installer.calls.isEmpty)
        #expect(harness.alerts.shown.isEmpty)

        // Clicking again starts again.
        harness.controller.startUpdate()
        #expect(harness.controller.row == .downloading(Self.version, progress: nil))
        try await waitUntil { harness.controller.row == .failed(Self.version) }
    }

    @Test func aFailedVerificationOffersToTryAgain() async throws {
        let harness = try await Self.harness()
        defer { harness.tearDown() }
        harness.installer.prepareError = .verification(.notNotarized)
        harness.controller.startUpdate()
        try await waitUntil { harness.controller.row == .failed(Self.version) }
        #expect(harness.opened().isEmpty)
        #expect(harness.relaunches() == 0)
        #expect(Self.cachedFiles(harness).isEmpty)

        harness.installer.prepareError = nil
        harness.controller.startUpdate()
        try await waitUntil { harness.relaunches() == 1 }
    }

    /// When trrek cannot replace itself, the release page opens and the row offers it again.
    @Test func aLocationTrrekCannotReplaceOpensTheReleasePage() async throws {
        for error in [UpdateInstallError.location(.notWritable), .location(.translocated), .extraction, .replacement] {
            let harness = try await Self.harness()
            defer { harness.tearDown() }
            if error == .replacement {
                harness.installer.installError = error
            } else {
                harness.installer.prepareError = error
            }
            harness.controller.startUpdate()
            try await waitUntil { harness.controller.row == .browser(Self.version) }
            let page = try #require(harness.controller.availableUpdate?.pageURL)
            #expect(harness.opened() == [page])
            #expect(harness.relaunches() == 0)
            #expect(harness.alerts.shown.isEmpty)

            let prepared = harness.installer.calls.count
            harness.controller.startUpdate()
            #expect(harness.opened() == [page, page])
            #expect(harness.installer.calls.count == prepared)
        }
    }

    @Test func aFailedRelaunchOffersToRelaunch() async throws {
        let harness = try await Self.harness(relaunchSucceeds: false)
        defer { harness.tearDown() }
        harness.controller.startUpdate()
        try await waitUntil { harness.controller.row == .relaunch(Self.version) }
        #expect(harness.relaunches() == 1)
        harness.controller.startUpdate()
        #expect(harness.relaunches() == 2)
        #expect(harness.installer.calls.count(where: { $0.hasPrefix("prepare") }) == 1)
    }

    /// While the update runs, clicks and checks do nothing.
    @Test func aSecondRequestDuringTheUpdateIsIgnored() async throws {
        let harness = try await Self.harness(downloader: .init(fails: false, delay: .milliseconds(300)))
        defer { harness.tearDown() }
        harness.controller.startUpdate()
        harness.controller.startUpdate()
        await harness.controller.checkManually()
        try await waitUntil { harness.relaunches() == 1 }
        #expect(harness.installer.calls.count(where: { $0.hasPrefix("prepare") }) == 1)
        #expect(await harness.feed.calls == 1)
        #expect(harness.alerts.shown.isEmpty)
    }

    /// A harness that knows 0.4.0 from an earlier check (stored), with no check done yet, so automatic checks are
    /// due; its feed answers `feedVersion` after `feedDelay`.
    private static func storedHarness(
        feedVersion: String,
        feedDelay: Duration = .zero,
        downloader: UpdateControllerTests.Downloader = .init(fails: false)
    ) throws -> Harness {
        let harness = try UpdateControllerTests.harness(
            feed: .success(UpdateControllerTests.releaseJSON(feedVersion)),
            downloader: downloader,
            feedDelay: feedDelay,
            suite: "trrek.tests.update-install"
        )
        let release = try ReleaseInfo.decode(UpdateControllerTests.releaseJSON("0.4.0"))
        UpdateStateStore(defaults: harness.defaults).availableUpdate = release
        #expect(harness.controller.row == .available(version))
        return harness
    }

    /// A click while a check runs is not lost: the update goes on with the known release.
    @Test func aClickDuringACheckStartsTheUpdate() async throws {
        // Long enough for the test to see the check running on a slow, busy runner.
        let harness = try Self.storedHarness(feedVersion: "0.4.0", feedDelay: .seconds(1))
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.isChecking }

        harness.controller.startUpdate()

        #expect(harness.controller.row == .downloading(Self.version, progress: nil))
        try await waitUntil { harness.relaunches() == 1 }
        #expect(harness.installer.calls.first == "prepare trrek-v0.4.0.dmg as 0.4.0 over 0.3.0")
    }

    /// A check that was already running when the update started cannot change it: neither "up to date" (the stored
    /// update is cleared) nor a newer release takes the row away or redirects the install.
    @Test func aCheckFinishingDuringTheUpdateDoesNotChangeIt() async throws {
        for answer in ["0.3.0", "0.5.0"] {
            let harness = try Self.storedHarness(
                feedVersion: answer,
                // The check must still be running when the update starts and finish while it downloads.
                feedDelay: .seconds(1),
                downloader: .init(fails: false, delay: .seconds(3))
            )
            defer { harness.tearDown() }
            harness.controller.checkAutomatically(.launch)
            try await waitUntil { harness.controller.isChecking }
            harness.controller.startUpdate()
            try await waitUntil { !harness.controller.isChecking }

            #expect(harness.controller.row?.version == Self.version)
            #expect(harness.controller.row?.isBusy == true)
            // A click on whatever the menu shows now does not start a second update.
            harness.controller.startUpdate()
            try await waitUntil { harness.relaunches() == 1 }
            #expect(harness.installer.calls == ["prepare trrek-v0.4.0.dmg as 0.4.0 over 0.3.0", "install"])
        }
    }

    /// While the update runs, an automatic check that is due sends no request and leaves the row alone.
    @Test func noAutomaticCheckDuringTheUpdate() async throws {
        let harness = try Self.storedHarness(
            feedVersion: "0.5.0",
            downloader: .init(fails: false, delay: .milliseconds(300))
        )
        defer { harness.tearDown() }
        harness.controller.startUpdate()
        harness.controller.checkAutomatically(.menuOpened)
        harness.controller.checkAutomatically(.wake)
        #expect(!harness.controller.isChecking)
        try await waitUntil { harness.relaunches() == 1 }
        #expect(await harness.feed.calls == 0)
        #expect(harness.rows().compactMap { $0?.version }.allSatisfy { $0 == Self.version })
    }

    /// A location trrek cannot replace itself in is found before downloading: the release page opens at once.
    @Test func aBadLocationOpensTheReleasePageBeforeDownloading() async throws {
        let harness = try await Self.harness()
        defer { harness.tearDown() }
        harness.installer.location = .translocated
        harness.controller.startUpdate()
        try await waitUntil { harness.controller.row == .browser(Self.version) }
        #expect(try harness.opened() == [#require(harness.controller.availableUpdate?.pageURL)])
        #expect(harness.installer.calls.isEmpty)
        #expect(!harness.rows().contains(.downloading(Self.version, progress: 0.5)))
        #expect(!FileManager.default.fileExists(atPath: harness.cache.path))
    }

    /// A release older than the running trrek (offered while checking as an assumed older version) is refused before
    /// anything is downloaded.
    @Test func anOlderReleaseThanTheRunningOneIsNotDownloaded() async throws {
        let harness = try UpdateControllerTests.harness(running: "0.5.0", suite: "trrek.tests.update-install")
        defer { harness.tearDown() }
        await harness.controller.checkManually()
        #expect(harness.controller.row == .available(Self.version))
        harness.controller.startUpdate()
        try await waitUntil { harness.controller.row == .failed(Self.version) }
        #expect(harness.installer.calls.isEmpty)
        #expect(!harness.rows().contains(.downloading(Self.version, progress: 0.5)))
        #expect(!FileManager.default.fileExists(atPath: harness.cache.path))
        #expect(harness.relaunches() == 0)
    }

    /// Disk images an interrupted update left in the cache folder are removed at launch, with mounts and backups.
    @Test func leftoversAreRemovedAtLaunch() async throws {
        let harness = try UpdateControllerTests.harness(suite: "trrek.tests.update-install")
        defer { harness.tearDown() }
        try FileManager.default.createDirectory(at: harness.cache, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: harness.cache.appendingPathComponent("trrek-v0.3.9.dmg"))
        harness.controller.cleanUpLeftovers()
        try await waitUntil { harness.installer.calls == ["clean up"] }
        #expect(!FileManager.default.fileExists(atPath: harness.cache.path))
    }
}
