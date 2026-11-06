import AppKit
import TrrekAppCore

/// An alert the update flow shows.
enum UpdateAlert: Equatable {
    /// A manual check found `release`; the primary button downloads it.
    case available(ReleaseInfo, current: SemanticVersion)
    case upToDate(current: SemanticVersion)
    case checkFailed(message: String)
    /// The primary button opens the release page.
    case downloadFailed(ReleaseInfo, message: String)
}

/// Shows update alerts; replaced by a fake in tests.
@MainActor
protocol UpdateAlertPresenting {
    /// Shows `alert`, as a sheet on `window` when there is one; returns whether the primary button was chosen.
    func present(_ alert: UpdateAlert, window: NSWindow?) async -> Bool
}

/// Posts the "update available" notification; replaced by a fake in tests.
@MainActor
protocol UpdateNotifying {
    func notify(_ release: ReleaseInfo)
}

/// Runs the update checks, the download and the alerts, and tells the menu and the settings window when its state
/// changes.
///
/// Checks run shortly after launch and after wake (one-shot delays, no repeating timer), when the menu opens and on
/// request; `UpdateChecker` decides whether an automatic one is due.
@MainActor
final class UpdateController {
    /// How long after launch and after wake the automatic check waits, so the network is up.
    static let settleDelay: TimeInterval = 10

    let checker: UpdateChecker
    private let downloader: UpdateDownloader
    private let notifier: any UpdateNotifying
    private let alerts: any UpdateAlertPresenting
    private let downloadsFolder: () -> URL?
    private let open: (URL) -> Void
    /// Shows a file in Finder without opening it.
    private let reveal: (URL) -> Void
    /// Whether automatic checks are on (the setting).
    private let automatic: () -> Bool
    /// Called whenever `availableUpdate`, `downloadingVersion`, `isChecking` or `lastCheck` may have changed.
    var onChange: (() -> Void)?

    /// The release being downloaded.
    private(set) var downloadingVersion: SemanticVersion?
    private var pendingCheck: DispatchWorkItem?

    init(
        checker: UpdateChecker,
        downloader: UpdateDownloader,
        notifier: any UpdateNotifying,
        alerts: any UpdateAlertPresenting,
        downloadsFolder: @escaping () -> URL? = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        reveal: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        automatic: @escaping () -> Bool
    ) {
        self.checker = checker
        self.downloader = downloader
        self.notifier = notifier
        self.alerts = alerts
        self.downloadsFolder = downloadsFolder
        self.open = open
        self.reveal = reveal
        self.automatic = automatic
        checker.onStateChange = { [weak self] in self?.onChange?() }
    }

    var availableUpdate: ReleaseInfo? {
        checker.availableUpdate
    }

    var isChecking: Bool {
        checker.isChecking
    }

    /// Whether a check or a download runs; Check for Updates… and Check Now are disabled meanwhile.
    var isBusy: Bool {
        isChecking || downloadingVersion != nil
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

    /// Checks if one is due for `trigger`; a newer release found for the first time posts a notification.
    func checkAutomatically(_ trigger: UpdateCheckTrigger) {
        guard checker.isDue(trigger, automatic: automatic()) else { return }
        Task {
            if case let .available(release, notify: true) = await checker.check(trigger, automatic: automatic()) {
                notifier.notify(release)
            }
        }
    }

    /// Check for Updates… and Check Now: checks and shows the outcome in an alert, as a sheet on the window `window`
    /// returns when it is still open. Returns once the alert is answered. Does nothing while a check or a download
    /// runs (the menu item and Check Now are disabled then).
    ///
    /// `window` is asked each time an alert is shown, so a closure holding the window weakly does not keep a closed
    /// settings window alive during a download.
    func checkManually(window: @escaping () -> NSWindow? = { nil }) async {
        guard !isBusy else { return }
        let result = await checker.check(.manual, automatic: automatic())
        let current = checker.currentVersion
        switch result {
        case let .available(release, _):
            if await alerts.present(.available(release, current: current), window: window()) {
                await download(window: window)
            }
        case .upToDate:
            _ = await alerts.present(.upToDate(current: current), window: window())
        case let .failed(message):
            _ = await alerts.present(.checkFailed(message: message), window: window())
        case .skipped:
            break
        }
    }

    // MARK: - Download

    /// Downloads the available update to the Downloads folder and opens the disk image (or only shows it in Finder
    /// when it could not be quarantined). A failure, including a refused Downloads folder, offers the release page
    /// instead. Does nothing while a download runs or when no update is known.
    func download(window: @escaping () -> NSWindow? = { nil }) async {
        guard let release = checker.availableUpdate, downloadingVersion == nil else { return }
        downloadingVersion = release.version
        onChange?()
        let result: Result<DownloadedDiskImage, any Error>
        do {
            guard let folder = downloadsFolder() else { throw CocoaError(.fileNoSuchFile) }
            result = try await .success(downloader.download(release, to: folder))
        } catch {
            result = .failure(error)
        }
        downloadingVersion = nil
        onChange?()
        switch result {
        case let .success(image) where image.isQuarantined:
            appLogger.notice("downloaded \(image.file.lastPathComponent, privacy: .public)")
            open(image.file)
        case let .success(image):
            appLogger
                .error("\(image.file.lastPathComponent, privacy: .public) is not quarantined; showing it in Finder")
            reveal(image.file)
        case let .failure(error):
            appLogger.error("update download failed: \(String(describing: error), privacy: .public)")
            let message = UpdateChecker.message(for: error)
            if await alerts.present(.downloadFailed(release, message: message), window: window()) {
                open(release.pageURL)
            }
        }
    }

    /// A click on the notification for `version` starts the download of the known update. When none is known any
    /// more (a later check found trrek up to date, or trrek was updated since), it checks by hand, so the click
    /// always shows something.
    func notificationOpened(version: String?) async {
        appLogger.notice("update notification opened for \(version ?? "?", privacy: .public)")
        if checker.availableUpdate != nil {
            await download()
        } else {
            await checkManually()
        }
    }

    func cancelPendingCheck() {
        pendingCheck?.cancel()
        pendingCheck = nil
    }
}
