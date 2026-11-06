import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// The update flow with a fake feed, downloader, notifier and alerts; nothing touches the network or the screen.
@MainActor
@Suite(.serialized)
struct UpdateControllerTests {
    private nonisolated static let suiteName = "trrek.tests.update-controller"

    private actor Feed: ReleaseFeed {
        let result: Result<Data, any Error>
        let delay: Duration
        private(set) var calls = 0

        init(_ result: Result<Data, any Error>, delay: Duration = .zero) {
            self.result = result
            self.delay = delay
        }

        func latestRelease() async throws -> Data {
            calls += 1
            try await Task.sleep(for: delay)
            return try result.get()
        }
    }

    private struct Downloader: FileDownloading {
        let fails: Bool

        func download(from _: URL) async throws -> URL {
            if fails {
                throw URLError(.timedOut)
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("dmg".utf8).write(to: file)
            return file
        }
    }

    private final class Notifier: UpdateNotifying {
        var posted: [SemanticVersion] = []

        func notify(_ release: ReleaseInfo) {
            posted.append(release.version)
        }
    }

    private final class Alerts: UpdateAlertPresenting {
        var shown: [UpdateAlert] = []
        var answer = true

        func present(_ alert: UpdateAlert, window _: NSWindow?) async -> Bool {
            shown.append(alert)
            return answer
        }
    }

    private struct Harness {
        let controller: UpdateController
        let feed: Feed
        let notifier: Notifier
        let alerts: Alerts
        let folder: URL
        let defaults: UserDefaults
        let opened: () -> [URL]

        func tearDown() {
            defaults.removePersistentDomain(forName: UpdateControllerTests.suiteName)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static let releases = "https://github.com/burakseyitkara1/trrek-releases/releases"

    static func releaseJSON(_ version: String) -> Data {
        Data("""
        {"tag_name": "v\(version)", "html_url": "\(releases)/tag/v\(version)", "body": "- New",
         "draft": false, "prerelease": false,
         "assets": [{"name": "trrek-v\(version).dmg",
                     "browser_download_url": "\(releases)/download/v\(version)/trrek-v\(version).dmg"}]}
        """.utf8)
    }

    private static func harness(
        current: String = "0.3.0",
        feed: Result<Data, any Error> = .success(releaseJSON("0.4.0")),
        automatic: Bool = true,
        downloadFails: Bool = false,
        feedDelay: Duration = .zero
    ) throws -> Harness {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fakeFeed = Feed(feed, delay: feedDelay)
        let notifier = Notifier()
        let alerts = Alerts()
        var opened: [URL] = []
        let checker = try UpdateChecker(
            currentVersion: #require(SemanticVersion(current)),
            feed: fakeFeed,
            state: UpdateStateStore(defaults: defaults)
        )
        let controller = UpdateController(
            checker: checker,
            downloader: UpdateDownloader(client: Downloader(fails: downloadFails)),
            notifier: notifier,
            alerts: alerts,
            downloadsFolder: { folder },
            open: { opened.append($0) },
            automatic: { automatic }
        )
        return Harness(
            controller: controller,
            feed: fakeFeed,
            notifier: notifier,
            alerts: alerts,
            folder: folder,
            defaults: defaults,
            opened: { opened }
        )
    }

    @Test func anAutomaticCheckNotifiesOncePerVersion() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        var changes = 0
        harness.controller.onChange = { changes += 1 }

        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.availableUpdate != nil && !harness.controller.isChecking }
        try await waitUntil { !harness.notifier.posted.isEmpty }
        #expect(harness.notifier.posted == [SemanticVersion("0.4.0")])
        #expect(harness.controller.availableUpdate?.version == SemanticVersion("0.4.0"))
        #expect(harness.controller.lastCheck != nil)
        #expect(changes >= 2)
        #expect(harness.alerts.shown.isEmpty)

        // The next automatic triggers within a day send no request and post nothing.
        harness.controller.checkAutomatically(.menuOpened)
        harness.controller.checkAutomatically(.wake)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await harness.feed.calls == 1)
        #expect(harness.notifier.posted.count == 1)
    }

    @Test func automaticChecksOffSendNothing() async throws {
        let harness = try Self.harness(automatic: false)
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await harness.feed.calls == 0)
        #expect(harness.controller.availableUpdate == nil)
    }

    @Test func aManualCheckShowsTheOutcome() async throws {
        let upToDate = try Self.harness(current: "0.4.0", automatic: false)
        defer { upToDate.tearDown() }
        await upToDate.controller.checkManually()
        #expect(try upToDate.alerts.shown == [.upToDate(current: #require(SemanticVersion("0.4.0")))])

        let offline = try Self.harness(feed: .failure(URLError(.notConnectedToInternet)))
        defer { offline.tearDown() }
        await offline.controller.checkManually()
        guard case let .checkFailed(message) = offline.alerts.shown.first else {
            Issue.record("expected the failure alert, got \(offline.alerts.shown)")
            return
        }
        #expect(!message.isEmpty)
        #expect(offline.notifier.posted.isEmpty)
    }

    @Test func aManualCheckOffersTheDownloadAndOpensTheDiskImage() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        var downloading: [SemanticVersion?] = []
        harness.controller.onChange = { downloading.append(harness.controller.downloadingVersion) }

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        #expect(try harness.alerts.shown == [.available(release, current: #require(SemanticVersion("0.3.0")))])
        #expect(harness.notifier.posted.isEmpty)
        let file = harness.folder.appendingPathComponent("trrek-v0.4.0.dmg")
        #expect(harness.opened() == [file])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(downloading.contains(SemanticVersion("0.4.0")))
        #expect(harness.controller.downloadingVersion == nil)
    }

    @Test func laterDoesNotDownload() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        harness.alerts.answer = false
        await harness.controller.checkManually()
        #expect(harness.opened().isEmpty)
        #expect(harness.controller.availableUpdate != nil)
    }

    @Test func aFailedDownloadOffersTheReleasePage() async throws {
        let harness = try Self.harness(downloadFails: true)
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.availableUpdate != nil && !harness.controller.isChecking }
        let release = try #require(harness.controller.availableUpdate)

        await harness.controller.notificationOpened(version: "0.4.0")

        guard case let .downloadFailed(failed, message) = harness.alerts.shown.first else {
            Issue.record("expected the download failure alert, got \(harness.alerts.shown)")
            return
        }
        #expect(failed == release)
        #expect(!message.isEmpty)
        #expect(harness.opened() == [release.pageURL])
        #expect(harness.controller.downloadingVersion == nil)
    }

    @Test func noDownloadWithoutAKnownUpdate() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        await harness.controller.download()
        #expect(harness.opened().isEmpty)
        #expect(harness.alerts.shown.isEmpty)
    }

    /// A Downloads folder trrek may not write to (the user refused the system prompt) ends in the failure alert, whose
    /// button opens the release page.
    @Test func aRefusedDownloadsFolderOffersTheReleasePage() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: harness.folder.path)

        await harness.controller.checkManually()

        let release = try #require(harness.controller.availableUpdate)
        #expect(harness.alerts.shown.count == 2)
        guard case let .downloadFailed(failed, message) = harness.alerts.shown.last else {
            Issue.record("expected the download failure alert, got \(harness.alerts.shown)")
            return
        }
        #expect(failed == release)
        #expect(!message.isEmpty)
        #expect(harness.opened() == [release.pageURL])
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.folder.path).isEmpty)
    }

    /// A click on a notification whose update is no longer known checks by hand, so it always shows something.
    @Test func aClickWithoutAKnownUpdateChecks() async throws {
        let harness = try Self.harness(current: "0.4.0")
        defer { harness.tearDown() }
        await harness.controller.notificationOpened(version: "0.4.0")
        #expect(try harness.alerts.shown == [.upToDate(current: #require(SemanticVersion("0.4.0")))])
        #expect(harness.opened().isEmpty)
    }

    /// While a check runs, a manual check does nothing (its menu item and Check Now are disabled).
    @Test func noManualCheckWhileBusy() async throws {
        let harness = try Self.harness(feedDelay: .milliseconds(300))
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.isBusy }
        #expect(harness.controller.isBusy)
        await harness.controller.checkManually()
        #expect(harness.alerts.shown.isEmpty)
        try await waitUntil { !harness.controller.isBusy }
        #expect(await harness.feed.calls == 1)
    }
}

/// The alerts' texts, the settings model's update line and the notification delegate.
@MainActor
struct UpdatePresentationTests {
    @Test func alertsHaveTheirButtons() throws {
        let release = try ReleaseInfo.decode(UpdateControllerTests.releaseJSON("0.4.0"))
        let current = try #require(SemanticVersion("0.3.0"))
        let available = SystemUpdateAlerts.makeAlert(.available(release, current: current))
        #expect(available.messageText == "trrek 0.4.0 is available")
        #expect(available.informativeText == "You have trrek 0.3.0.\n\n• New")
        #expect(available.buttons.map(\.title) == ["Download", "Later"])

        let failed = SystemUpdateAlerts.makeAlert(.downloadFailed(release, message: "Offline"))
        #expect(failed.messageText == "Couldn’t download trrek 0.4.0")
        #expect(failed.buttons.map(\.title) == ["Open Download Page", "Cancel"])

        #expect(SystemUpdateAlerts.makeAlert(.upToDate(current: current)).messageText == "trrek is up to date")
        #expect(SystemUpdateAlerts.makeAlert(.checkFailed(message: "x")).buttons.map(\.title) == ["OK"])
    }

    @Test func settingsModelShowsTheLastCheck() {
        var requested = 0
        let model = SettingsModel(
            settings: AppSettings(),
            backlightAvailable: true,
            checkForUpdates: { _ in requested += 1 },
            onChange: { _ in }
        )
        #expect(model.updateCheckStatus == "Not checked yet")
        model.lastUpdateCheck = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(model.updateCheckStatus.hasPrefix("Last checked: "))
        model.isCheckingForUpdates = true
        #expect(model.updateCheckStatus == "Checking…")
        model.checkForUpdatesNow()
        #expect(requested == 1)
    }

    @Test func theNotificationCenterIsLeftAloneOutsideTheAppBundle() {
        // The test runner is not trrek's bundle; touching the center there would raise.
        #expect(UpdateNotificationDelegate.center == nil)
        UpdateNotificationDelegate().install()
    }

    @Test func aClickBeforeTheHandlerIsSetIsDeliveredOnce() {
        let delegate = UpdateNotificationDelegate()
        delegate.opened(version: "0.4.0")
        var opened: [String?] = []
        delegate.onOpen = { opened.append($0) }
        #expect(opened == ["0.4.0"])
        delegate.onOpen = { opened.append($0) }
        #expect(opened == ["0.4.0"])
        delegate.opened(version: "0.5.0")
        #expect(opened == ["0.4.0", "0.5.0"])
    }
}
