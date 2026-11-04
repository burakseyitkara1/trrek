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

    /// Updates the icon and the menu contents.
    func refresh() {
        refreshIcon()
        rebuild()
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

    private func rebuild() {
        menu.removeAllItems()
        guard let coordinator else { return }
        let settings = coordinator.settings

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
        menu.addItem(item(String(localized: "Quit trrek", bundle: .main), #selector(quit), key: "q"))
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

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
