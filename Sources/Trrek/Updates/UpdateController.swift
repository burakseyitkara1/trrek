import AppKit
import TrrekAppCore
import TrrekPlatform

/// An alert a manual check shows: only its outcome when there is nothing to update, since a found update shows in
/// the menu bar icon, the menu and General instead.
enum UpdateAlert: Equatable {
    case upToDate(current: SemanticVersion)
    case checkFailed(message: String)
}

/// Shows update alerts; replaced by a fake in tests.
@MainActor
protocol UpdateAlertPresenting {
    /// Shows `alert`, as a sheet on `window` when there is one, and returns once it is dismissed.
    func present(_ alert: UpdateAlert, window: NSWindow?) async
}

/// Runs the update checks and the update itself, and tells the menu and the settings window when its state changes.
///
/// Checks run shortly after launch and after wake (one-shot delays, no repeating timer), when the menu opens and on
/// request; `UpdateChecker` decides whether an automatic one is due. A known update shows as a badge on the menu bar
/// icon and a row at the top of the menu (`row`); choosing the row downloads the disk image into the app's caches,
/// verifies and installs it, and relaunches, with no further question.
@MainActor
final class UpdateController {
    /// How long after launch and after wake the automatic check waits, so the network is up.
    static let settleDelay: TimeInterval = 10

    let checker: UpdateChecker
    private let downloader: UpdateDownloader
    private let installer: any UpdateInstalling
    /// The version of the trrek that is running; no older release is downloaded (tests pass their own).
    private let runningVersion: SemanticVersion
    /// Quits and opens the (replaced) app bundle again; returns `false` when it could not.
    private let relaunch: () -> Bool
    private let alerts: any UpdateAlertPresenting
    /// Where the disk image is downloaded; emptied at launch.
    private let cacheFolder: URL
    /// Opens the release page in the browser.
    private let open: (URL) -> Void
    /// Whether automatic checks are on (the setting).
    private let automatic: () -> Bool
    /// Called whenever `row` appears or disappears, or `isChecking` or `lastCheck` may have changed.
    var onChange: (() -> Void)?
    /// Called with `row` whenever it changes, also for each visible step of the download progress; on the main queue,
    /// which the run loop also serves while the menu is tracking.
    var onRowChange: ((UpdateRowState?) -> Void)?

    /// The update run once the row was chosen: the release it started with, and its progress or how it ended.
    private var flow: (release: ReleaseInfo, state: UpdateRowState)?
    private var pendingCheck: DispatchWorkItem?

    init(
        checker: UpdateChecker,
        downloader: UpdateDownloader,
        installer: any UpdateInstalling,
        runningVersion: SemanticVersion = UpdateInstaller.runningVersion,
        relaunch: @escaping () -> Bool = { Relauncher.relaunch(reason: "update") },
        alerts: any UpdateAlertPresenting,
        cacheFolder: URL = UpdateController.defaultCacheFolder,
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        automatic: @escaping () -> Bool
    ) {
        self.checker = checker
        self.downloader = downloader
        self.installer = installer
        self.runningVersion = runningVersion
        self.relaunch = relaunch
        self.alerts = alerts
        self.cacheFolder = cacheFolder
        self.open = open
        self.automatic = automatic
        checker.onStateChange = { [weak self] in self?.changed() }
    }

    /// `~/Library/Caches/com.burakseyitkara.trrek/Updates`.
    nonisolated static var defaultCacheFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(AppIdentity.bundleID).appendingPathComponent("Updates")
    }

    var availableUpdate: ReleaseInfo? {
        checker.availableUpdate
    }

    /// The update row in the menu and in General; `nil` when no update is known. A running update (and an installed
    /// one waiting for its relaunch) keeps its row whatever a check found meanwhile; a failed one shows while its
    /// release is still the known update.
    var row: UpdateRowState? {
        if let flow, flow.state.isBusy || flow.state.isAwaitingRelaunch {
            return flow.state
        }
        guard let release = checker.availableUpdate else { return nil }
        if let flow, flow.release.version == release.version {
            return flow.state
        }
        return .available(release.version)
    }

    /// Whether a download or an install runs.
    var isUpdating: Bool {
        flow?.state.isBusy ?? false
    }

    var isChecking: Bool {
        checker.isChecking
    }

    /// Whether a check or an update runs; Check for Updates… and Check Now are disabled meanwhile.
    var isBusy: Bool {
        isChecking || isUpdating
    }

    var lastCheck: Date? {
        checker.lastCheck
    }

    // MARK: - Checks

    /// Runs an automatic check for `trigger` once, after `delay`; a later request replaces a pending one.
    func schedule(_ trigger: UpdateCheckTrigger, after delay: TimeInterval = settleDelay) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingCheck = nil
                self?.checkAutomatically(trigger)
            }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Checks if one is due for `trigger`; a newer release shows as the badge and the menu row. Nothing is checked
    /// while an update runs.
    func checkAutomatically(_ trigger: UpdateCheckTrigger) {
        guard !isUpdating, checker.isDue(trigger, automatic: automatic()) else { return }
        Task { _ = await checker.check(trigger, automatic: automatic()) }
    }

    /// Check for Updates… in the menu: checks, and shows an alert (as a sheet on the window `window` returns when it
    /// is still open) only when trrek is up to date or the check failed; a found update shows as the badge, the menu
    /// row and the line in General. Does nothing while a check or an update runs.
    func checkManually(window: @escaping () -> NSWindow? = { nil }) async {
        guard !isBusy else { return }
        let result = await checker.check(.manual, automatic: automatic())
        switch result {
        case .upToDate:
            await alerts.present(.upToDate(current: checker.currentVersion), window: window())
        case let .failed(message):
            await alerts.present(.checkFailed(message: message), window: window())
        case .available, .skipped:
            break
        }
    }

    /// Check Now in General: the same check as `checkManually`, but the outcome is returned for the settings window to
    /// show on its update line instead of in an alert. `nil` when a release was found (the line shows it) or nothing
    /// was checked because a check or an update was already running.
    func checkForSettings() async -> UpdateAlert? {
        guard !isBusy else { return nil }
        switch await checker.check(.manual, automatic: automatic()) {
        case .upToDate:
            return .upToDate(current: checker.currentVersion)
        case let .failed(message):
            return .checkFailed(message: message)
        case .available, .skipped:
            return nil
        }
    }

    func cancelPendingCheck() {
        pendingCheck?.cancel()
        pendingCheck = nil
    }

    // MARK: - Update

    /// The row was chosen (or Update Now): starts the update of the known release, or after a failure starts it
    /// again; in the browser state opens the release page again; after an install whose relaunch failed, relaunches.
    /// A check still running does not hold it up (the update goes on with the release known now and the check's
    /// outcome no longer changes the row); a second click while an update runs does nothing.
    func startUpdate() {
        if let flow {
            if flow.state.isBusy {
                return
            }
            if flow.state.isAwaitingRelaunch {
                _ = relaunch()
                return
            }
        }
        guard let release = checker.availableUpdate, var state = row else { return }
        if case .browser = state {
            open(release.pageURL)
            return
        }
        guard state.start() else { return }
        appLogger.notice("update \(release.version, privacy: .public) started")
        flow = (release, state)
        changed()
        Task { await run(release) }
    }

    /// Checks that trrek can replace itself, downloads, verifies and installs `release`, then relaunches. Every step
    /// changes only the update it started (`release.version`). The row keeps showing the download while the
    /// downloader retries; a final failure carries its `UpdateFailure`.
    private func run(_ release: ReleaseInfo) async {
        let version = release.version
        // An older release than this build is refused before anything is downloaded (the installer checks again).
        if UpdateInstallPolicy.downgradeProblem(version: version, running: runningVersion) != nil {
            appLogger.error("update \(version, privacy: .public) is older than this build; not downloading")
            update(version) { $0.fail(.verification) }
            return
        }
        if let issue = await installer.locationIssue() {
            appLogger.notice("update install not possible here: \(String(describing: issue), privacy: .public)")
            fallBackToBrowser(release)
            return
        }
        let report: @MainActor (Int64, Int64) -> Void = { [weak self] received, expected in
            self?.progress(received: received, expected: expected, version: version)
        }
        let image: DownloadedDiskImage
        do {
            image = try await downloader.download(release, to: cacheFolder) { received, expected in
                DispatchQueue.main.async { report(received, expected) }
            }
        } catch {
            // The downloader has already retried a transient failure.
            appLogger.error("update download failed", error)
            update(version) { $0.fail(UpdateFailure(error)) }
            return
        }
        update(version) { $0.downloaded() }
        do {
            let staged = try await installer.prepare(
                image: image.file,
                version: version,
                current: checker.currentVersion
            )
            try await installer.install(staged)
        } catch {
            removeDownload(image.file)
            appLogger.error("update install failed: \(String(describing: error), privacy: .public)")
            if error.fallsBackToBrowser {
                fallBackToBrowser(release)
            } else {
                update(version) { $0.fail(UpdateFailure(error)) }
            }
            return
        }
        removeDownload(image.file)
        if !relaunch() {
            update(version) { $0.installedWithoutRelaunch() }
        }
    }

    private func fallBackToBrowser(_ release: ReleaseInfo) {
        update(release.version) { $0.fallBackToBrowser() }
        open(release.pageURL)
    }

    private func progress(received: Int64, expected: Int64, version: SemanticVersion) {
        guard var flow, flow.release.version == version,
              flow.state.progress(received: received, expected: expected)
        else { return }
        self.flow = flow
        onRowChange?(row)
    }

    /// Changes the running update's state, only when it is still the update of `version`.
    private func update(_ version: SemanticVersion, _ change: (inout UpdateRowState) -> Void) {
        guard var flow, flow.release.version == version else { return }
        change(&flow.state)
        self.flow = flow
        changed()
    }

    private func changed() {
        onChange?()
        onRowChange?(row)
    }

    private func removeDownload(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    /// Removes what an interrupted update left: disk images in the cache folder, mounted images and the previous
    /// app's backup; once, at launch.
    func cleanUpLeftovers() {
        let installer = installer
        let folder = cacheFolder
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folder)
            await installer.cleanUpLeftovers()
        }
    }
}
