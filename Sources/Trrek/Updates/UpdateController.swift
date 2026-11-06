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
    /// The downloaded app was verified; the primary button installs it and relaunches.
    case readyToInstall(ReleaseInfo)
    /// trrek cannot replace itself (`message` says why); the disk image is opened after the alert.
    case installFallback(ReleaseInfo, message: String)
    /// The downloaded app failed verification; the primary button opens the release page.
    case verificationFailed(ReleaseInfo, message: String)
    /// The update was installed but trrek could not relaunch itself.
    case relaunchNeeded(ReleaseInfo)
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
    /// Installs a downloaded update in place; without one the disk image is opened, as before in-place installs.
    private let installer: (any UpdateInstalling)?
    /// Quits and opens the (replaced) app bundle again; returns `false` when it could not.
    private let relaunch: () -> Bool
    private let notifier: any UpdateNotifying
    private let alerts: any UpdateAlertPresenting
    private let downloadsFolder: () -> URL?
    private let open: (URL) -> Void
    /// Shows a file in Finder without opening it.
    private let reveal: (URL) -> Void
    /// Whether automatic checks are on (the setting).
    private let automatic: () -> Bool
    /// Called whenever `availableUpdate`, `downloadingVersion`, `installingVersion`, `pendingInstall`, `isChecking` or
    /// `lastCheck` may have changed.
    var onChange: (() -> Void)?

    /// The release being downloaded.
    private(set) var downloadingVersion: SemanticVersion?
    /// The release being verified, offered or installed, and which of those.
    private(set) var installingVersion: SemanticVersion?
    private(set) var installPhase: InstallPhase?
    /// The release installed over the running app when trrek could not relaunch; nothing more is offered until it
    /// is restarted.
    private(set) var installedVersion: SemanticVersion?
    /// The verified app waiting for the user's answer; removed when trrek quits meanwhile.
    private var stagedUpdate: StagedUpdate?
    /// A downloaded update the user chose to install later; the menu offers "Install trrek X.Y.Z…".
    private(set) var pendingInstall: PendingInstall?
    private var pendingCheck: DispatchWorkItem?

    init(
        checker: UpdateChecker,
        downloader: UpdateDownloader,
        installer: (any UpdateInstalling)? = nil,
        relaunch: @escaping () -> Bool = { Relauncher.relaunch(reason: "update") },
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
        self.installer = installer
        self.relaunch = relaunch
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

    /// Whether a check, a download or an install runs; Check for Updates… and Check Now are disabled meanwhile.
    var isBusy: Bool {
        isChecking || downloadingVersion != nil || installingVersion != nil
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
        if let installed = installedVersion, let release = checker.availableUpdate, release.version == installed {
            _ = await alerts.present(.relaunchNeeded(release), window: window())
            return
        }
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

    /// Downloads the available update to the Downloads folder and installs it in place (`installOrOpen`), or opens
    /// the disk image without an installer. A failure, including a refused Downloads folder, offers the release page
    /// instead. Does nothing while a download or an install runs or when no update is known.
    func download(window: @escaping () -> NSWindow? = { nil }) async {
        guard let release = checker.availableUpdate, downloadingVersion == nil, installingVersion == nil,
              installedVersion == nil
        else { return }
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
        case let .success(image):
            appLogger.notice("downloaded \(image.file.lastPathComponent, privacy: .public)")
            if installer == nil {
                openDiskImage(image)
            } else {
                await installOrOpen(image, release: release, window: window)
            }
        case let .failure(error):
            appLogger.error("update download failed: \(String(describing: error), privacy: .public)")
            let message = UpdateChecker.message(for: error)
            if await alerts.present(.downloadFailed(release, message: message), window: window()) {
                open(release.pageURL)
            }
        }
    }

    /// Opens the disk image, or only shows it in Finder when it could not be quarantined.
    func openDiskImage(_ image: DownloadedDiskImage) {
        if image.isQuarantined {
            open(image.file)
        } else {
            appLogger
                .error("\(image.file.lastPathComponent, privacy: .public) is not quarantined; showing it in Finder")
            reveal(image.file)
        }
    }

    /// A click on the notification for `version` installs an update kept for later, or starts the download of the
    /// known update. When none is known any more (a later check found trrek up to date, or trrek was updated since),
    /// it checks by hand, so the click always shows something.
    func notificationOpened(version: String?) async {
        appLogger.notice("update notification opened for \(version ?? "?", privacy: .public)")
        if installedVersion != nil {
            await checkManually()
        } else if pendingInstall != nil {
            await installPending()
        } else if checker.availableUpdate != nil {
            await download()
        } else {
            await checkManually()
        }
    }

    /// Removes what an interrupted install left (mounted images, the previous app's backup); once, at launch.
    func cleanUpLeftovers() {
        guard let installer else { return }
        Task { await installer.cleanUpLeftovers() }
    }

    /// Removes a staged update whose alert is still open when trrek quits.
    func discardStagedUpdate() {
        guard let staged = stagedUpdate else { return }
        stagedUpdate = nil
        try? FileManager.default.removeItem(at: staged.folder)
    }

    func cancelPendingCheck() {
        pendingCheck?.cancel()
        pendingCheck = nil
    }
}

/// What the install of a downloaded update is doing; the menu names it.
enum InstallPhase: Equatable {
    /// Mounting the disk image and verifying the app.
    case verifying
    /// Waiting for the answer to "trrek X.Y.Z is ready to install".
    case ready
    /// Verifying again and replacing the app.
    case installing
}

/// A downloaded disk image kept for a later install.
struct PendingInstall: Equatable {
    let release: ReleaseInfo
    let image: DownloadedDiskImage
}

// MARK: - Install

extension UpdateController {
    /// Verifies the app in the downloaded disk image and asks whether to install it now. Install and Relaunch
    /// replaces trrek's bundle and relaunches; Later keeps the disk image for "Install trrek X.Y.Z…". When trrek
    /// cannot replace itself, the disk image is opened after an alert that says why; a failed verification shows an
    /// error and keeps the disk image without opening it.
    func installOrOpen(
        _ image: DownloadedDiskImage,
        release: ReleaseInfo,
        window: @escaping () -> NSWindow? = { nil }
    ) async {
        guard let installer, installingVersion == nil, installedVersion == nil else { return }
        pendingInstall = nil
        installingVersion = release.version
        enter(.verifying)
        let staged: StagedUpdate
        do {
            staged = try await installer.prepare(
                image: image.file,
                version: release.version,
                current: checker.currentVersion
            )
        } catch {
            await installFailed(error, image: image, release: release, window: window)
            return
        }
        stagedUpdate = staged
        enter(.ready)
        let accepted = await alerts.present(.readyToInstall(release), window: window())
        stagedUpdate = nil
        guard accepted else {
            await installer.discard(staged)
            pendingInstall = PendingInstall(release: release, image: image)
            finishInstall()
            return
        }
        enter(.installing)
        do {
            try await installer.install(staged)
        } catch {
            await installFailed(error, image: image, release: release, window: window)
            return
        }
        installedVersion = release.version
        if !relaunch() {
            finishInstall()
            _ = await alerts.present(.relaunchNeeded(release), window: window())
        }
    }

    private func enter(_ phase: InstallPhase) {
        installPhase = phase
        onChange?()
    }

    /// "Install trrek X.Y.Z…": verifies the kept disk image again and offers it; downloads it again when it is gone.
    func installPending(window: @escaping () -> NSWindow? = { nil }) async {
        guard let pending = pendingInstall, !isBusy, installedVersion == nil else { return }
        guard FileManager.default.fileExists(atPath: pending.image.file.path) else {
            appLogger.notice("\(pending.image.file.lastPathComponent, privacy: .public) is gone; downloading again")
            pendingInstall = nil
            onChange?()
            await download(window: window)
            return
        }
        await installOrOpen(pending.image, release: pending.release, window: window)
    }

    private func installFailed(
        _ error: UpdateInstallError,
        image: DownloadedDiskImage,
        release: ReleaseInfo,
        window: () -> NSWindow?
    ) async {
        finishInstall()
        if error.fallsBackToDiskImage {
            _ = await alerts.present(.installFallback(release, message: error.message), window: window())
            openDiskImage(image)
        } else if await alerts.present(.verificationFailed(release, message: error.message), window: window()) {
            open(release.pageURL)
        }
    }

    private func finishInstall() {
        installingVersion = nil
        installPhase = nil
        onChange?()
    }
}
