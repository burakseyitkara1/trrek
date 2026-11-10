import AppKit
import TrrekAppCore
import TrrekEngine

/// The update check and the update: created at launch, shown on the menu bar icon, in the menu and in General.
extension Coordinator {
    /// Creates the update controller and schedules the launch check.
    func startUpdates(assumedVersion: SemanticVersion?) {
        guard let running = SemanticVersion(TrrekVersion.string) else { return }
        let current = assumedVersion ?? running
        var defaults = UserDefaults.standard
        if let assumedVersion {
            guard let suite = UserDefaults(suiteName: UpdateStateStore.assumedVersionSuite) else { return }
            defaults = suite
            appLogger.notice("update check assumes version \(assumedVersion, privacy: .public)")
        }
        let state = UpdateStateStore(defaults: defaults)
        let updates = UpdateController(
            checker: UpdateChecker(currentVersion: current, feed: ReleaseFeedClient(), state: state),
            downloader: UpdateDownloader(),
            installer: UpdateInstaller(bundle: Bundle.main.bundleURL),
            automatic: { [weak self] in self?.settings.checkForUpdatesAutomatically ?? false }
        )
        updates.onChange = { [weak self] in self?.updateStateChanged() }
        updates.onRowChange = { [weak self] row in self?.updateRowChanged(row) }
        self.updates = updates
        updates.cleanUpLeftovers()
        updates.schedule(.launch)
    }

    /// Update Now (and Try Again, Update in Browser…, Relaunch) in General: the same as choosing the menu row.
    var startUpdateAction: () -> Void {
        { [weak self] in self?.updates?.startUpdate() }
    }

    /// Check Now in the settings window: a manual check whose outcome (up to date, or why it failed) shows on the
    /// update line in General.
    var checkForUpdatesAction: (NSWindow?) -> Void {
        { [weak self] _ in
            guard let updates = self?.updates else { return }
            Task { [weak self] in
                let outcome = await updates.checkManually()
                self?.windows.settingsModel?.updateCheckNote = outcome?.note
            }
        }
    }

    /// Shows the update state in the menu and the open settings window.
    func updateStateChanged() {
        statusMenu?.refresh()
        if let model = windows.settingsModel {
            showUpdateState(in: model)
        }
    }

    /// Shows a changed update row (also each step of the download, and a check starting or ending) in the menu, open
    /// or not, and in General.
    func updateRowChanged(_: UpdateRowState?) {
        statusMenu?.showUpdateState()
        if let model = windows.settingsModel {
            showUpdateState(in: model)
        }
    }

    /// Copies the last check time, the update row and whether a check or an update runs into the settings window's
    /// model.
    func showUpdateState(in model: SettingsModel) {
        guard let updates else { return }
        model.lastUpdateCheck = updates.lastCheck
        model.isCheckingForUpdates = updates.isChecking
        model.isUpdateBusy = updates.isBusy
        model.updateRow = updates.row
    }
}
