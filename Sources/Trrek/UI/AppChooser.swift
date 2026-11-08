import AppKit
import UniformTypeIdentifiers

/// The open panel for choosing apps from `/Applications`, shared by the paused apps list and the Edges tab.
@MainActor
enum AppChooser {
    /// Shows the panel as a sheet on the settings window and passes the chosen apps to `completion`; nothing is
    /// passed when it is cancelled. The window comes from the model rather than `NSApp.keyWindow`, which is `nil` when
    /// the click that opens the panel is also the one that brings trrek to the front. trrek itself is skipped by the
    /// callers.
    static func choose(
        title: String,
        allowsMultipleSelection: Bool,
        model: SettingsModel,
        completion: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = String(localized: "Add", bundle: .main)
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard let window = model.window ?? NSApp.keyWindow, window.isVisible else {
            if panel.runModal() == .OK {
                completion(panel.urls)
            }
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            completion(panel.urls)
        }
    }
}
