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

        menu.addItem(item("Precision Control", #selector(togglePrecision), checked: settings.precision))
        menu.addItem(item("Freeze Cursor", #selector(toggleFreezeCursor), checked: settings.freezeCursor))
        if settings.holdKeyMode == .toggle, settings.holdKey != .none {
            let state = coordinator.isHoldToggleActive ? "On" : "Off"
            let holdItem = NSMenuItem(title: "Hold-to-Slide: \(state)", action: nil, keyEquivalent: "")
            holdItem.isEnabled = false
            menu.addItem(holdItem)
        }
        // The same app as the status line, also while a trrek window is in front.
        if let (id, name) = coordinator.pauseTargetApp {
            if settings.pausedBundleIDs.contains(id) {
                menu.addItem(item("Resume in \(name)", #selector(resumeInFrontApp)))
            } else {
                menu.addItem(item("Pause in \(name)", #selector(pauseInFrontApp)))
            }
        }
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Show Welcome", #selector(showWelcome)))
        if !coordinator.isTrusted {
            menu.addItem(item("Grant Accessibility…", #selector(grantAccessibility)))
        }
        menu.addItem(.separator())

        menu.addItem(item("About trrek", #selector(showAbout)))
        menu.addItem(item("Quit trrek", #selector(quit), key: "q"))
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
