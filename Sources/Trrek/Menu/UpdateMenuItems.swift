import AppKit
import TrrekAppCore

/// The menu items that follow the update: the update row (a view, so a click keeps the menu open), Check for
/// Updates… (disabled while a check or an update runs) and Quit trrek (disabled while trrek replaces itself, so the
/// final verification and the relaunch are not cut short). They are updated in place, also while the menu is open.
@MainActor
final class UpdateMenuItems {
    private(set) var row: UpdateRowView?
    private(set) weak var checkItem: NSMenuItem?
    private(set) weak var quitItem: NSMenuItem?

    /// Forgets the items of the previous menu; called before it is rebuilt.
    func reset() {
        row = nil
        checkItem = nil
        quitItem = nil
    }

    /// The update row's item: `onClick` handles a click in the view; Return on the highlighted row sends `action`.
    func makeRowItem(
        _ state: UpdateRowState,
        target: AnyObject,
        action: Selector,
        onClick: @escaping () -> Void
    ) -> NSMenuItem {
        let view = UpdateRowView(state: state)
        view.onClick = onClick
        let item = NSMenuItem(title: state.title, action: action, keyEquivalent: "")
        item.target = target
        item.view = view
        item.isEnabled = state.isClickable
        row = view
        return item
    }

    /// Keeps the Check for Updates… and Quit trrek items, and sets them for `row` and `isBusy`.
    func track(check: NSMenuItem, quit: NSMenuItem, row: UpdateRowState?, isBusy: Bool) {
        checkItem = check
        quitItem = quit
        updateCommands(row: row, isBusy: isBusy)
    }

    /// Shows `row` and `isBusy` in place. Returns whether the menu must be rebuilt because the row appeared or
    /// disappeared.
    func show(row state: UpdateRowState?, isBusy: Bool) -> Bool {
        updateCommands(row: state, isBusy: isBusy)
        if let state, let row {
            row.state = state
            return false
        }
        return (state == nil) != (row == nil)
    }

    private func updateCommands(row: UpdateRowState?, isBusy: Bool) {
        checkItem?.isEnabled = !isBusy
        if case .installing = row {
            quitItem?.isEnabled = false
        } else {
            quitItem?.isEnabled = true
        }
    }
}
