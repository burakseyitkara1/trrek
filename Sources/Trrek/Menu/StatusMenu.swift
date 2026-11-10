import AppKit
import TrrekAppCore
import TrrekPlatform

/// The menu bar item and its menu, rebuilt each time the menu opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private weak var coordinator: Coordinator?
    /// The state the icon was last drawn for.
    private var iconState: MenuIcon.State?
    /// The update items of the menu built last, updated in place while the menu is open.
    let updateItems = UpdateMenuItems()
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
        let state = MenuIcon.State(
            active: coordinator?.isHoldToggleActive ?? false,
            attention: !(coordinator?.isTrusted ?? true),
            update: coordinator?.updates?.row != nil
        )
        guard state != iconState else { return }
        iconState = state
        statusItem.button?.image = MenuIcon.image(state)
    }

    /// Shows the update controller's state in the update row, in place (also while the menu is open, so a found
    /// update and the download's progress show without moving any item).
    func showUpdateState() {
        refreshIcon()
        let updates = coordinator?.updates
        updateItems.show(update: updates?.row)
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
        updateItems.menuClosed()
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

        updateItems.reset()
        addStatusLines(coordinator: coordinator)
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
        addUpdateRow(coordinator: coordinator)
        let quit = item(String(localized: "Quit trrek", bundle: .main), #selector(quit), key: "q")
        menu.addItem(quit)
        updateItems.track(quit: quit)
    }

    /// The update row: Check for Updates, its outcome, or the known update.
    private func addUpdateRow(coordinator: Coordinator) {
        let updates = coordinator.updates
        updateItems.show(update: updates?.row)
        let known = [updates?.row?.version, updates?.availableUpdate?.version].compactMap(\.self)
        let action = #selector(chooseUpdateRow)
        let item = updateItems.makeRowItem(known: known, target: self, action: action) { [weak self] in
            self?.chooseUpdateRow()
        }
        menu.addItem(item)
    }

    /// The status line, and under it the app in front while its own edges apply.
    private func addStatusLines(coordinator: Coordinator) {
        let settings = coordinator.settings
        let isActive = coordinator.isTrusted && coordinator.trackpadIssue == nil
        let profileLine = coordinator.pauseTargetApp.flatMap { app in
            StatusText.edgeProfileLine(
                bundleID: app.bundleID,
                appName: app.name,
                settings: settings,
                isActive: isActive
            )
        }
        for line in [coordinator.statusText, profileLine].compactMap(\.self) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
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

    /// A click on the update row, or Return on it (which closes the menu first; a check's outcome then shows the
    /// next time it opens): checks, or starts the known update.
    @objc private func chooseUpdateRow() {
        guard let updates = coordinator?.updates else { return }
        switch updateItems.click() {
        case .check:
            Task { [weak self] in
                let outcome = await updates.checkManually()
                self?.updateItems.finishCheck(outcome, update: updates.row)
            }
        case .update:
            updates.startUpdate()
        case .nothing:
            break
        }
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
