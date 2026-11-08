import AppKit
import TrrekAppCore

/// Update alerts as `NSAlert`s: a sheet on the given window, otherwise an app-modal alert with trrek brought to the
/// front (it has no window of its own to attach to).
@MainActor
struct SystemUpdateAlerts: UpdateAlertPresenting {
    func present(_ alert: UpdateAlert, window: NSWindow?) async {
        let panel = Self.makeAlert(alert)
        NSApp.activate()
        if let window, window.isVisible, window.attachedSheet == nil {
            await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { _ in continuation.resume() }
            }
            return
        }
        panel.runModal()
    }

    static func makeAlert(_ alert: UpdateAlert) -> NSAlert {
        let panel = NSAlert()
        switch alert {
        case let .upToDate(current):
            panel.messageText = String(localized: "trrek is up to date", bundle: .main)
            panel.informativeText = String(
                localized: "trrek \(current.description) is the latest version.",
                bundle: .main
            )
        case let .checkFailed(message):
            panel.messageText = String(localized: "Couldn’t check for updates", bundle: .main)
            panel.informativeText = message
            panel.alertStyle = .warning
        }
        panel.addButton(withTitle: String(localized: "OK", bundle: .main))
        return panel
    }
}
