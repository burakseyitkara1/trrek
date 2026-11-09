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

    /// What an update alert says: its title, text, buttons and whether it is a warning.
    struct Content: Equatable {
        var title: String
        var message: String
        var buttons: [String]
        var isWarning = false
    }

    /// The alert's content, without creating an `NSAlert` (creating one needs the window server, which tests on a
    /// headless runner can wait on for a long time).
    static func content(of alert: UpdateAlert) -> Content {
        let ok = String(localized: "OK", bundle: .main)
        switch alert {
        case let .upToDate(current):
            return Content(
                title: String(localized: "trrek is up to date", bundle: .main),
                message: String(localized: "trrek \(current.description) is the latest version.", bundle: .main),
                buttons: [ok]
            )
        case let .checkFailed(message):
            return Content(
                title: String(localized: "Couldn’t check for updates", bundle: .main),
                message: message,
                buttons: [ok],
                isWarning: true
            )
        }
    }

    /// The outcome as one short line for General's update line: "trrek is up to date", or why the check failed.
    static func note(for alert: UpdateAlert) -> String {
        switch alert {
        case .upToDate:
            content(of: alert).title
        case .checkFailed:
            content(of: alert).message
        }
    }

    static func makeAlert(_ alert: UpdateAlert) -> NSAlert {
        let content = content(of: alert)
        let panel = NSAlert()
        panel.messageText = content.title
        panel.informativeText = content.message
        if content.isWarning {
            panel.alertStyle = .warning
        }
        for button in content.buttons {
            panel.addButton(withTitle: button)
        }
        return panel
    }
}
