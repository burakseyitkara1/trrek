import AppKit
import SwiftUI
import TrrekAppCore
import UniformTypeIdentifiers

/// "Export Settings…" and "Import Settings…" in the General tab. The panels open as sheets on the settings window.
struct SettingsTransferButtons: View {
    @Bindable var model: SettingsModel

    var body: some View {
        HStack {
            Button("Export Settings…", action: exportSettings)
            Button("Import Settings…", action: importSettings)
            Spacer()
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Settings", bundle: .main)
        panel.prompt = String(localized: "Export", bundle: .main)
        panel.nameFieldStringValue = SettingsDocument.defaultFileName
        panel.allowedContentTypes = [.trrekSettings]
        panel.canCreateDirectories = true
        let model = model
        SettingsPanels.present(panel, from: model) { model.exportSettings(to: $0) }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Settings", bundle: .main)
        panel.prompt = String(localized: "Import", bundle: .main)
        panel.allowedContentTypes = [.trrekSettings]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let model = model
        SettingsPanels.present(panel, from: model) { url in
            Task { await model.prepareImport(from: url) }
        }
    }
}

/// The import confirmation and the import/export failure alert, attached to the whole settings window so they also
/// show when a file opened from Finder arrives while another tab is selected.
struct SettingsTransferAlerts: ViewModifier {
    @Bindable var model: SettingsModel

    func body(content: Content) -> some View {
        content
            .alert(
                Self.importTitle(model.pendingImport),
                isPresented: $model.isConfirmingImport,
                presenting: model.pendingImport
            ) { pending in
                // The captured value, not `model.pendingImport`: it is applied whatever the closing order.
                Button("Replace", role: .destructive) { model.confirmImport(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Launch at Login and the language keep their current settings.")
            }
            .alert(
                model.transferFailure?.title ?? String(localized: "Import Failed", bundle: .main),
                isPresented: $model.isShowingTransferFailure,
                presenting: model.transferFailure
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }

    /// The pending import is kept after the alert closes, so the title stays the same while it animates out.
    static func importTitle(_ pending: PendingImport?) -> String {
        guard let pending else { return String(localized: "Replace your current settings?", bundle: .main) }
        return String(
            localized: "Replace your current settings with the ones in “\(pending.fileName)”?",
            bundle: .main
        )
    }
}

@MainActor
private enum SettingsPanels {
    /// Shows `panel` as a sheet on the settings window and passes the chosen file to `completion`. The window
    /// comes from the model rather than `NSApp.keyWindow`, which is `nil` when the click that reaches the button is
    /// also the one that brings trrek to the front; without a visible window the panel runs on its own.
    static func present(_ panel: NSSavePanel, from model: SettingsModel, completion: @escaping (URL) -> Void) {
        guard let window = model.window ?? NSApp.keyWindow, window.isVisible else {
            if panel.runModal() == .OK, let url = panel.url {
                completion(url)
            }
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}

extension UTType {
    /// A `.trrek` settings file, declared by the app's Info.plist.
    static let trrekSettings = UTType(exportedAs: SettingsDocument.typeIdentifier, conformingTo: .json)
}
