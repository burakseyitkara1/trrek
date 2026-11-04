import AppKit
import TrrekAppCore

/// Settings read from a file, shown in the import confirmation.
struct PendingImport {
    let fileName: String
    let settings: AppSettings
}

/// An import or export that failed: the alert's title and explanation.
struct TransferFailure {
    let title: String
    let message: String
}

/// Exporting the settings to, and importing them from, a `.trrek` file.
extension SettingsModel {
    /// Whether an import confirmation or a failure is showing, or a file is being read.
    var isTransferBusy: Bool {
        isConfirmingImport || isShowingTransferFailure || isReadingImport
    }

    /// Whether a file opened from Finder must wait: the window already shows an alert or a sheet (such as an open
    /// panel), or is reading another file.
    var isBusyForOpenedFile: Bool {
        isTransferBusy || confirmingReset || window?.attachedSheet != nil
    }

    /// Writes the current settings to `url`; a failure is shown in an alert.
    func exportSettings(to url: URL) {
        do {
            try SettingsDocument.encode(settings).write(to: url, options: .atomic)
        } catch {
            appLogger.error("settings export failed: \(String(describing: error), privacy: .public)")
            showFailure(TransferFailure(
                title: String(localized: "The settings could not be exported.", bundle: .main),
                message: error.localizedDescription
            ))
        }
    }

    /// A settings file opened from Finder. While the window is busy (`isBusyForOpenedFile`) the file is ignored
    /// rather than queued: replacing a confirmation the user is reading, or stacking a second alert behind it, could
    /// import a file other than the one named. The user can open it again once the alert is answered.
    func openedFile(at url: URL) async {
        guard !isBusyForOpenedFile else {
            appLogger.notice("settings file ignored while the settings window is busy")
            return
        }
        await prepareImport(from: url)
    }

    /// Reads the file at `url` off the main actor and asks to replace the current settings with it. A file that
    /// cannot be read, is too large or is not a settings file shows an alert instead; the settings stay as they are
    /// until the import is confirmed. Ignored while another import or failure is showing.
    func prepareImport(from url: URL) async {
        guard !isTransferBusy else { return }
        isReadingImport = true
        let result = await Self.readSettings(at: url)
        isReadingImport = false
        let fileName = url.lastPathComponent
        switch result {
        case let .success(settings):
            pendingImport = PendingImport(fileName: fileName, settings: settings)
            isConfirmingImport = true
        case let .failure(failure):
            showFailure(TransferFailure(
                title: String(localized: "“\(fileName)” could not be imported.", bundle: .main),
                message: failure.text
            ))
        }
    }

    /// Replaces the settings with `pending`, the import the confirmation was shown for, keeping Launch at Login and
    /// whether the welcome window was shown. Taking the value (rather than reading `pendingImport`) makes Replace
    /// work whatever the order in which the alert closes and runs its action. The change reaches the store and the
    /// engine like any other.
    func confirmImport(_ pending: PendingImport) {
        isConfirmingImport = false
        settings = SettingsDocument.imported(pending.settings, into: settings)
    }

    private func showFailure(_ failure: TransferFailure) {
        isConfirmingImport = false
        transferFailure = failure
        isShowingTransferFailure = true
    }

    /// Reads and decodes a settings file; runs on the global executor, so a slow volume does not block the window.
    private nonisolated static func readSettings(at url: URL) async -> Result<AppSettings, ImportFailureMessage> {
        do {
            return try .success(SettingsDocument.decode(SettingsDocument.read(contentsOf: url)))
        } catch let error as SettingsDocumentError {
            appLogger.error("settings import refused: \(String(describing: error), privacy: .public)")
            return .failure(ImportFailureMessage(error.message))
        } catch {
            appLogger.error("settings file unreadable: \(String(describing: error), privacy: .public)")
            return .failure(ImportFailureMessage(
                String(localized: "The file could not be read. Your settings were not changed.", bundle: .main)
            ))
        }
    }
}

/// The explanation for a refused import.
private struct ImportFailureMessage: Error {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}
