import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// Counts a fake downloader's attempts.
final class DownloadAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

/// The update checks with a fake feed; nothing touches the network or the screen.
@MainActor
@Suite(.serialized)
struct UpdateControllerTests {
    nonisolated static let suiteName = "trrek.tests.update-controller"

    actor Feed: ReleaseFeed {
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

    /// Records the install steps; each fails with its configured error.
    final class Installer: UpdateInstalling, @unchecked Sendable {
        var prepareError: UpdateInstallError?
        var installError: UpdateInstallError?
        private(set) var calls: [String] = []

        func prepare(
            image: URL,
            version: SemanticVersion,
            current: SemanticVersion
        ) async throws(UpdateInstallError) -> StagedUpdate {
            calls.append("prepare \(image.lastPathComponent) as \(version) over \(current)")
            if let prepareError {
                throw prepareError
            }
            let folder = image.deletingLastPathComponent().appendingPathComponent("staging")
            let app = folder.appendingPathComponent("trrek.app")
            return StagedUpdate(app: app, folder: folder, version: version, current: current)
        }

        func install(_: StagedUpdate) async throws(UpdateInstallError) {
            calls.append("install")
            if let installError {
                throw installError
            }
        }

        /// What `locationIssue()` answers before the download.
        var location: InstallLocationIssue?

        func locationIssue() async -> InstallLocationIssue? {
            location
        }

        func cleanUpLeftovers() async {
            calls.append("clean up")
        }
    }

    struct Harness {
        let controller: UpdateController
        let feed: Feed
        let installer: Installer
        let folder: URL
        let defaults: UserDefaults
        let suite: String
        let opened: () -> [URL]
        let relaunches: () -> Int
        let rows: () -> [UpdateRowState?]

        var cache: URL {
            folder.appendingPathComponent("Caches/Updates")
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static let releases = "https://github.com/burakseyitkara1/trrek/releases"

    static func releaseJSON(_ version: String) -> Data {
        Data("""
        {"tag_name": "v\(version)", "html_url": "\(releases)/tag/v\(version)", "body": "- New",
         "draft": false, "prerelease": false,
         "assets": [{"name": "trrek-v\(version).dmg",
                     "browser_download_url": "\(releases)/download/v\(version)/trrek-v\(version).dmg"}]}
        """.utf8)
    }

    static func harness(
        current: String = "0.3.0",
        running: String = "0.3.0",
        feed: Result<Data, any Error> = .success(releaseJSON("0.4.0")),
        automatic: Bool = true,
        downloader: Downloader = Downloader(fails: false),
        feedDelay: Duration = .zero,
        relaunchSucceeds: Bool = true,
        suite: String = suiteName,
        retryWait: @escaping RetrySleeper = { _ in }
    ) throws -> Harness {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fakeFeed = Feed(feed, delay: feedDelay)
        let installer = Installer()
        var opened: [URL] = []
        var relaunches = 0
        var rows: [UpdateRowState?] = []
        let checker = try UpdateChecker(
            currentVersion: #require(SemanticVersion(current)),
            feed: fakeFeed,
            state: UpdateStateStore(defaults: defaults)
        )
        let controller = try UpdateController(
            checker: checker,
            downloader: UpdateDownloader(client: downloader, retry: RetryPolicy(sleep: retryWait)),
            installer: installer,
            runningVersion: #require(SemanticVersion(running)),
            relaunch: {
                relaunches += 1
                return relaunchSucceeds
            },
            cacheFolder: folder.appendingPathComponent("Caches/Updates"),
            open: { opened.append($0) },
            automatic: { automatic }
        )
        controller.onRowChange = { row in
            #expect(Thread.isMainThread)
            if rows.last != .some(row) {
                rows.append(row)
            }
        }
        return Harness(
            controller: controller,
            feed: fakeFeed,
            installer: installer,
            folder: folder,
            defaults: defaults,
            suite: suite,
            opened: { opened },
            relaunches: { relaunches },
            rows: { rows }
        )
    }

    @Test func anAutomaticCheckShowsTheRow() async throws {
        let harness = try Self.harness()
        defer { harness.tearDown() }
        var changes = 0
        harness.controller.onChange = { changes += 1 }

        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.availableUpdate != nil && !harness.controller.isChecking }

        let version = try #require(SemanticVersion("0.4.0"))
        #expect(harness.controller.row == .available(version))
        #expect(harness.rows().last == .some(.available(version)))
        #expect(harness.controller.lastCheck != nil)
        #expect(changes >= 2)

        // The next automatic triggers within a day send no request.
        harness.controller.checkAutomatically(.menuOpened)
        harness.controller.checkAutomatically(.wake)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await harness.feed.calls == 1)
    }

    @Test func automaticChecksOffSendNothing() async throws {
        let harness = try Self.harness(automatic: false)
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await harness.feed.calls == 0)
        #expect(harness.controller.row == nil)
    }

    /// A manual check (Check for Updates in the menu, Check Now in General) returns its outcome for the menu row or
    /// General's update line; a found release is no outcome, it shows as the row.
    @Test func aManualCheckReturnsTheOutcome() async throws {
        let upToDate = try Self.harness(current: "0.4.0", automatic: false)
        defer { upToDate.tearDown() }
        #expect(await upToDate.controller.checkManually() == .upToDate)
        #expect(upToDate.controller.row == nil)

        let offline = try Self.harness(feed: .failure(URLError(.notConnectedToInternet)))
        defer { offline.tearDown() }
        let outcome = await offline.controller.checkManually()
        #expect(outcome == .checkFailed(message: "You appear to be offline."))
        #expect(outcome?.note == "You appear to be offline.")

        let found = try Self.harness(suite: "trrek.tests.update-controller.found")
        defer { found.tearDown() }
        #expect(await found.controller.checkManually() == nil)
        #expect(try found.controller.row == .available(#require(SemanticVersion("0.4.0"))))
    }

    /// While a check runs, a manual check does nothing (its menu item and Check Now are disabled).
    @Test func noManualCheckWhileBusy() async throws {
        let harness = try Self.harness(feedDelay: .milliseconds(300))
        defer { harness.tearDown() }
        harness.controller.checkAutomatically(.launch)
        try await waitUntil { harness.controller.isBusy }
        #expect(await harness.controller.checkManually() == nil)
        try await waitUntil { !harness.controller.isBusy }
        #expect(await harness.feed.calls == 1)
    }

    @Test func settingsModelShowsTheLastCheckAndStartsTheUpdate() {
        var requested = 0
        var started = 0
        let model = SettingsModel(
            settings: AppSettings(),
            backlightAvailable: true,
            checkForUpdates: { _ in requested += 1 },
            startUpdate: { started += 1 },
            onChange: { _ in }
        )
        #expect(model.updateCheckStatus == "Not checked yet")
        model.lastUpdateCheck = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(model.updateCheckStatus.hasPrefix("Last checked: "))
        model.isCheckingForUpdates = true
        #expect(model.updateCheckStatus == "Checking…")
        model.checkForUpdatesNow()
        #expect(requested == 1)
        #expect(model.updateRow == nil)
        model.updateNow()
        #expect(started == 1)
    }
}

extension UpdateControllerTests {
    /// Writes a small file, reporting half and then all of it; can fail (always, or its first `failFirst` attempts,
    /// with `error`, after reporting half when `halfBeforeFailing`) or take a while.
    struct Downloader: FileDownloading {
        let fails: Bool
        var delay: Duration = .zero
        var failFirst = 0
        var error = URLError(.timedOut)
        var halfBeforeFailing = false
        let attempts = DownloadAttempts()

        func download(from _: URL, progress: @escaping DownloadProgress) async throws -> URL {
            let attempt = attempts.next()
            progress(0, -1)
            try await Task.sleep(for: delay)
            if fails || attempt <= failFirst {
                if halfBeforeFailing {
                    progress(50, 100)
                }
                throw error
            }
            progress(50, 100)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("dmg".utf8).write(to: file)
            progress(100, 100)
            return file
        }
    }
}
