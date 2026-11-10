import AppKit
import TrrekAppCore

/// The menu items that follow the update: the update row (a view, so a click keeps the menu open) and Quit trrek
/// (disabled while trrek replaces itself, so the final verification and the relaunch are not cut short). The row's
/// state outlives the menu's rebuilds (a check started in one menu ends in a later one); the items are updated in
/// place, also while the menu is open.
@MainActor
final class UpdateMenuItems {
    private(set) var state = MenuUpdateRowState()
    private(set) var row: UpdateRowView?
    private(set) weak var quitItem: NSMenuItem?

    /// Forgets the items of the previous menu; called before it is rebuilt.
    func reset() {
        row = nil
        quitItem = nil
    }

    /// The update row's item: `onClick` handles a click in the view; Return on the highlighted row sends `action`.
    /// Its width fits every state with `known`, the update known now.
    func makeRowItem(
        known: SemanticVersion?,
        target: AnyObject,
        action: Selector,
        onClick: @escaping () -> Void
    ) -> NSMenuItem {
        let width = UpdateRowView.width(for: MenuUpdateRowState.widthSamples(known: known))
        let view = UpdateRowView(state: state, width: width)
        view.onClick = onClick
        let item = NSMenuItem(title: state.title, action: action, keyEquivalent: "")
        item.target = target
        item.view = view
        item.isEnabled = state.isClickable
        row = view
        return item
    }

    /// Keeps the Quit trrek item and sets it for the current state.
    func track(quit: NSMenuItem) {
        quitItem = quit
        apply()
    }

    /// The update controller's state, shown in place.
    func show(update: UpdateRowState?, isCheckRunning: Bool) {
        state.show(update: update, isCheckRunning: isCheckRunning)
        apply()
    }

    /// A click on the row (or Return): what the caller should do.
    func click() -> MenuUpdateRowState.Click {
        let click = state.click()
        apply()
        return click
    }

    /// The check the row started ended.
    func finishCheck(_ outcome: UpdateCheckOutcome?, update: UpdateRowState?) {
        state.finishCheck(outcome, update: update)
        apply()
    }

    func menuClosed() {
        state.menuClosed()
        apply()
    }

    private func apply() {
        row?.state = state
        if case .update(.installing) = state.phase {
            quitItem?.isEnabled = false
        } else {
            quitItem?.isEnabled = true
        }
    }
}
