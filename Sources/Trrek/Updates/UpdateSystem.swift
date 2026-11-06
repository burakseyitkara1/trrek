import AppKit
import TrrekAppCore
import UserNotifications

/// Update alerts as `NSAlert`s: a sheet on the given window, otherwise an app-modal alert with trrek brought to the
/// front (it has no window of its own to attach to).
@MainActor
struct SystemUpdateAlerts: UpdateAlertPresenting {
    func present(_ alert: UpdateAlert, window: NSWindow?) async -> Bool {
        let panel = Self.makeAlert(alert)
        NSApp.activate()
        if let window, window.isVisible, window.attachedSheet == nil {
            let response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
            return response == .alertFirstButtonReturn
        }
        return panel.runModal() == .alertFirstButtonReturn
    }

    static func makeAlert(_ alert: UpdateAlert) -> NSAlert {
        let panel = NSAlert()
        switch alert {
        case let .available(release, current):
            panel.messageText = String(localized: "trrek \(release.version.description) is available", bundle: .main)
            let installed = String(localized: "You have trrek \(current.description).", bundle: .main)
            let notes = ReleaseInfo.excerpt(of: release.notes)
            panel.informativeText = notes.isEmpty ? installed : installed + "\n\n" + notes
            panel.addButton(withTitle: String(localized: "Download", bundle: .main))
            panel.addButton(withTitle: String(localized: "Later", bundle: .main))
        case let .upToDate(current):
            panel.messageText = String(localized: "trrek is up to date", bundle: .main)
            panel.informativeText = String(
                localized: "trrek \(current.description) is the latest version.",
                bundle: .main
            )
            panel.addButton(withTitle: String(localized: "OK", bundle: .main))
        case let .checkFailed(message):
            panel.messageText = String(localized: "Couldn’t check for updates", bundle: .main)
            panel.informativeText = message
            panel.alertStyle = .warning
            panel.addButton(withTitle: String(localized: "OK", bundle: .main))
        case let .downloadFailed(release, message):
            panel.messageText = String(
                localized: "Couldn’t download trrek \(release.version.description)",
                bundle: .main
            )
            panel.informativeText = message
            panel.alertStyle = .warning
            panel.addButton(withTitle: String(localized: "Open Download Page", bundle: .main))
            panel.addButton(withTitle: String(localized: "Cancel", bundle: .main))
        case .readyToInstall, .installFallback, .verificationFailed, .relaunchNeeded:
            configureInstallAlert(panel, alert)
        }
        return panel
    }

    /// The alerts of the in-place install.
    private static func configureInstallAlert(_ panel: NSAlert, _ alert: UpdateAlert) {
        switch alert {
        case let .readyToInstall(release):
            panel.messageText = String(
                localized: "trrek \(release.version.description) is ready to install",
                bundle: .main
            )
            panel.informativeText = String(localized: "trrek will quit and open again.", bundle: .main)
            panel.addButton(withTitle: String(localized: "Install and Relaunch", bundle: .main))
            panel.addButton(withTitle: String(localized: "Later", bundle: .main))
        case let .installFallback(release, message):
            panel.messageText = String(
                localized: "trrek \(release.version.description) couldn’t be installed automatically",
                bundle: .main
            )
            let drag = String(
                localized: "Drag trrek to the Applications folder in the disk image’s window.",
                bundle: .main
            )
            panel.informativeText = message + "\n\n" + drag
            panel.addButton(withTitle: String(localized: "OK", bundle: .main))
        case let .verificationFailed(release, message):
            panel.messageText = String(
                localized: "trrek \(release.version.description) couldn’t be verified",
                bundle: .main
            )
            let kept = String(localized: "Nothing was installed. The disk image is kept in Downloads.", bundle: .main)
            panel.informativeText = message + "\n\n" + kept
            panel.alertStyle = .critical
            panel.addButton(withTitle: String(localized: "Open Download Page", bundle: .main))
            panel.addButton(withTitle: String(localized: "Cancel", bundle: .main))
        case let .relaunchNeeded(release):
            panel.messageText = String(localized: "trrek \(release.version.description) is installed", bundle: .main)
            panel.informativeText = String(
                localized: "Quit trrek and open it again to use the new version.",
                bundle: .main
            )
            panel.addButton(withTitle: String(localized: "OK", bundle: .main))
        case .available, .upToDate, .checkFailed, .downloadFailed:
            break
        }
    }
}

/// Posts the update notification through the system notification center. Authorization is requested the first
/// time a notification is needed; without it nothing is posted and the menu item is the only sign of the update.
@MainActor
struct SystemUpdateNotifier: UpdateNotifying {
    /// The key of the notification's version in its user info.
    nonisolated static let versionKey = "version"

    func notify(_ release: ReleaseInfo) {
        guard let center = UpdateNotificationDelegate.center else { return }
        let version = release.version.description
        let content = UNMutableNotificationContent()
        content.title = String(localized: "trrek \(version) is available", bundle: .main)
        content.body = String(localized: "Click to download.", bundle: .main)
        content.userInfo = [Self.versionKey: version]
        let request = UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil)
        Task {
            do {
                guard try await center.requestAuthorization(options: [.alert]) else {
                    appLogger.notice("update notification not allowed; the menu shows the update")
                    return
                }
                try await center.add(request)
                appLogger.notice("update notification posted for \(version, privacy: .public)")
            } catch {
                appLogger.error("update notification failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

/// Receives clicks on trrek's notifications. Installed as the notification center's delegate at launch, before a
/// click that launched trrek is delivered; a click that arrives before `onOpen` is set is kept until it is.
@MainActor
final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// The notification center, only inside trrek's app bundle: outside one (`swift run`, tests) the system has no
    /// app to attribute notifications to and the center must not be touched.
    static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == AppIdentity.bundleID ? UNUserNotificationCenter.current() : nil
    }

    /// Called with the clicked notification's version.
    var onOpen: ((String?) -> Void)? {
        didSet {
            guard let onOpen, let pending = pendingClicks.popLast() else { return }
            pendingClicks.removeAll()
            onOpen(pending)
        }
    }

    private var pendingClicks: [String?] = []

    func install() {
        Self.center?.delegate = self
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let version = response.notification.request.content.userInfo[SystemUpdateNotifier.versionKey] as? String
        await opened(version: version)
    }

    /// Shows the banner also while a trrek window is in front.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Passes a click to `onOpen`, or keeps it until `onOpen` is set.
    func opened(version: String?) {
        if let onOpen {
            onOpen(version)
        } else {
            pendingClicks.append(version)
        }
    }
}
