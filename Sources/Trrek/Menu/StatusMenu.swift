import AppKit
import TrrekAppCore
import TrrekPlatform

/// The menu bar item and its menu, rebuilt each time the menu opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private weak var coordinator: Coordinator?
    /// The state the icon was last drawn for: hold toggle on, Accessibility missing.
    private var iconState: (active: Bool, attention: Bool)?
    /// Whether the menu is showing. Changes that arrive meanwhile (an update check started by opening it) are built
    /// when it closes, so items never move under the pointer.
    private var isOpen = false
    private var needsRebuild = false

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "trrek"
        refresh()
    }

    /// Updates the icon and the menu contents; while the menu shows, the contents wait until it closes.
    func refresh() {
        refreshIcon()
        if isOpen {
            needsRebuild = true
        } else {
            rebuild()
        }
    }

    func refreshIcon() {
        let active = coordinator?.isHoldToggleActive ?? false
        let attention = !(coordinator?.isTrusted ?? true)
        if let iconState, iconState == (active, attention) {
            return
        }
        iconState = (active, attention)
        statusItem.button?.image = MenuIcon.image(active: active, attention: attention)
    }

    func menuNeedsUpdate(_: NSMenu) {
        rebuild()
    }

    func menuWillOpen(_: NSMenu) {
        isOpen = true
        coordinator?.updates?.checkAutomatically(.menuOpened)
    }

    /// The chosen item's action is sent after this, so the pending rebuild waits for the next main-queue turn.
    func menuDidClose(_: NSMenu) {
        isOpen = false
        guard needsRebuild else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen, self.needsRebuild else { return }
                self.rebuild()
            }
        }
    }

    private func rebuild() {
        needsRebuild = false
        menu.removeAllItems()
        guard let coordinator else { return }
        let settings = coordinator.settings

        if let updateItem = updateItem(coordinator.updates) {
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }
        let status = NSMenuItem(title: coordinator.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let precision = String(localized: "Precision Control", bundle: .main)
        menu.addItem(item(precision, #selector(togglePrecision), checked: settings.precision))
        let freezeCursor = String(localized: "Freeze Cursor", bundle: .main)
        menu.addItem(item(freezeCursor, #selector(toggleFreezeCursor), checked: settings.freezeCursor))
        if settings.holdKeyMode == .toggle, settings.holdKey != .none {
            let title = coordinator.isHoldToggleActive
                ? String(localized: "Hold-to-Slide: On", bundle: .main)
                : String(localized: "Hold-to-Slide: Off", bundle: .main)
            let holdItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holdItem.isEnabled = false
            menu.addItem(holdItem)
        }
        // The same app as the status line, also while a trrek window is in front.
        if let (id, name) = coordinator.pauseTargetApp {
            if settings.pausedBundleIDs.contains(id) {
                menu.addItem(item(String(localized: "Resume in \(name)", bundle: .main), #selector(resumeInFrontApp)))
            } else {
                menu.addItem(item(String(localized: "Pause in \(name)", bundle: .main), #selector(pauseInFrontApp)))
            }
        }
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "Settings…", bundle: .main), #selector(openSettings), key: ","))
        menu.addItem(item(String(localized: "Show Welcome", bundle: .main), #selector(showWelcome)))
        if !coordinator.isTrusted {
            let grant = String(localized: "Grant Accessibility…", bundle: .main)
            menu.addItem(item(grant, #selector(grantAccessibility)))
        }
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "About trrek", bundle: .main), #selector(showAbout)))
        let checkForUpdates = item(String(localized: "Check for Updates…", bundle: .main), #selector(checkForUpdates))
        checkForUpdates.isEnabled = !(coordinator.updates?.isBusy ?? false)
        menu.addItem(checkForUpdates)
        menu.addItem(item(String(localized: "Quit trrek", bundle: .main), #selector(quit), key: "q"))
    }

    /// "Update Available: trrek X.Y.Z…", or "Install trrek X.Y.Z…" for an update kept for later, in bold with a
    /// download symbol; disabled "Downloading…", "Verifying…", "… Is Ready to Install" or "Installing…" items while
    /// that runs; `nil` when no update is known or one was installed and trrek awaits a restart.
    private func updateItem(_ updates: UpdateController?) -> NSMenuItem? {
        guard let updates, updates.installedVersion == nil else { return nil }
        let busyTitle: String? = if let version = updates.downloadingVersion {
            String(localized: "Downloading trrek \(version.description)…", bundle: .main)
        } else if let version = updates.installingVersion {
            switch updates.installPhase {
            case .verifying:
                String(localized: "Verifying trrek \(version.description)…", bundle: .main)
            case .ready:
                String(localized: "trrek \(version.description) Is Ready to Install", bundle: .main)
            case .installing, nil:
                String(localized: "Installing trrek \(version.description)…", bundle: .main)
            }
        } else {
            nil
        }
        if let busyTitle {
            let busy = NSMenuItem(title: busyTitle, action: nil, keyEquivalent: "")
            busy.isEnabled = false
            return busy
        }
        let title: String
        let action: Selector
        if let pending = updates.pendingInstall {
            title = String(localized: "Install trrek \(pending.release.version.description)…", bundle: .main)
            action = #selector(installUpdate)
        } else if let release = updates.availableUpdate {
            title = String(localized: "Update Available: trrek \(release.version.description)…", bundle: .main)
            action = #selector(downloadUpdate)
        } else {
            return nil
        }
        let update = item(title, action)
        update.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)]
        )
        update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        return update
    }

    private func item(_ title: String, _ action: Selector, key: String = "", checked: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let checked {
            item.state = checked ? .on : .off
        }
        return item
    }

    // MARK: - Actions

    @objc private func togglePrecision() {
        guard let coordinator else { return }
        var settings = coordinator.settings
        settings.precision.toggle()
        coordinator.apply(settings)
    }

    @objc private func toggleFreezeCursor() {
        guard let coordinator else { return }
        var settings = coordinator.settings
        settings.freezeCursor.toggle()
        coordinator.apply(settings)
    }

    @objc private func pauseInFrontApp() {
        coordinator?.pauseInFrontApp()
    }

    @objc private func resumeInFrontApp() {
        coordinator?.resumeInFrontApp()
    }

    @objc private func openSettings() {
        coordinator?.openSettings()
    }

    @objc private func showWelcome() {
        coordinator?.showWelcome()
    }

    @objc private func grantAccessibility() {
        coordinator?.grantAccessibility()
    }

    @objc private func downloadUpdate() {
        guard let updates = coordinator?.updates else { return }
        Task { await updates.download() }
    }

    @objc private func installUpdate() {
        guard let updates = coordinator?.updates else { return }
        Task { await updates.installPending() }
    }

    @objc private func checkForUpdates() {
        guard let updates = coordinator?.updates else { return }
        Task { await updates.checkManually() }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
