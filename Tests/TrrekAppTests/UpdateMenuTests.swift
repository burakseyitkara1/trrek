import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// The menu's update row view: its texts, icon, spinner, progress bar, enabled state and click handling. Views only;
/// no menu is opened and no window is created.
@MainActor
struct UpdateRowViewTests {
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    private final class Target: NSObject {
        var sent = 0

        @objc func chosen() {
            sent += 1
        }
    }

    private static func state(_ phase: MenuUpdateRowState.Phase) -> MenuUpdateRowState {
        var state = MenuUpdateRowState()
        switch phase {
        case let .update(row):
            state.show(update: row)
        case .idle:
            break
        case .checking:
            _ = state.click()
        case .upToDate:
            _ = state.click()
            state.finishCheck(.upToDate, update: nil)
        case let .checkFailed(reason):
            _ = state.click()
            state.finishCheck(.checkFailed(message: reason), update: nil)
        }
        #expect(state.phase == phase)
        return state
    }

    private static func makeView(_ phase: MenuUpdateRowState.Phase = .idle) -> UpdateRowView {
        UpdateRowView(state: state(phase), width: UpdateRowView.width(for: MenuUpdateRowState.widthSamples(known: [])))
    }

    @Test func checkStatesUpdateTitleAndIconInPlace() {
        let view = Self.makeView()
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        let height = view.frame.height
        view.layoutSubtreeIfNeeded()

        #expect(view.label.stringValue == "Check for Updates")
        #expect(view.label.font?.pointSize == NSFont.menuFont(ofSize: 0).pointSize)
        #expect(view.icon.isHidden)
        #expect(view.bar.isHidden)
        #expect(view.accessibilityRole() == .menuItem)

        view.state = Self.state(.checking)
        #expect(view.label.stringValue == "Checking for Updates…")
        #expect(view.icon.isHidden)
        #expect(!item.isEnabled)
        #expect(view.bar.isHidden)
        // Not in a window (no open menu), so the spinner does not animate.
        #expect(!view.isAnimating)

        view.state = Self.state(.upToDate)
        #expect(view.label.stringValue == "trrek Is Up to Date")
        #expect(!view.icon.isHidden)
        #expect(!item.isEnabled)

        view.state = Self.state(.checkFailed(reason: "You appear to be offline."))
        #expect(view.label.stringValue == "Couldn’t Check — Try Again")
        #expect(view.toolTip == "You appear to be offline.")
        #expect(view.accessibilityLabel() == "Couldn’t Check — Try Again. You appear to be offline.")
        #expect(item.isEnabled)

        // One height in every state, so the open menu keeps its layout; the title starts at the same place.
        #expect(view.frame.height == height)
        view.layoutSubtreeIfNeeded()
        #expect(view.label.frame.minX == UpdateRowView.titleX)
    }

    @Test func updateStatesUpdateTitleAndProgressInPlace() {
        let ver = Self.version
        let view = Self.makeView()
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        let height = view.frame.height

        view.state = Self.state(.update(.available(ver)))
        #expect(view.label.stringValue == "Update Available: trrek 0.4.0")
        #expect(view.accessibilityLabel() == "Update Available: trrek 0.4.0")
        #expect(view.toolTip == nil)
        #expect(!view.icon.isHidden)
        #expect(view.bar.isHidden)
        #expect(item.isEnabled)

        view.state = Self.state(.update(.downloading(ver, progress: nil)))
        #expect(view.label.stringValue == "Downloading trrek 0.4.0…")
        #expect(!view.bar.isHidden && view.bar.isIndeterminate)
        #expect(!item.isEnabled)

        view.state = Self.state(.update(.downloading(ver, progress: 0.42)))
        #expect(!view.bar.isIndeterminate)
        #expect(view.bar.doubleValue == 0.42)
        #expect(view.accessibilityValue() as? String == 0.42.formatted(.percent.precision(.fractionLength(0))))
        view.layoutSubtreeIfNeeded()
        #expect(view.label.frame.maxX <= view.bar.frame.minX)

        view.state = Self.state(.update(.installing(ver)))
        #expect(view.label.stringValue == "Installing trrek 0.4.0…")
        #expect(!view.bar.isHidden && view.bar.isIndeterminate)

        // The row stays short; the reason is in the tooltip and read out after the title.
        view.state = Self.state(.update(.failed(ver, reason: .serverUnavailable)))
        #expect(view.label.stringValue == "Update Failed — Try Again")
        #expect(view.bar.isHidden)
        #expect(view.toolTip == "GitHub isn’t responding. Try again in a few minutes.")
        #expect(view.accessibilityLabel()
            == "Update Failed — Try Again. GitHub isn’t responding. Try again in a few minutes.")

        // One height in every state, so the open menu keeps its layout; the title starts at the same place.
        #expect(view.frame.height == height)
        #expect(height == UpdateRowView.height)
        view.layoutSubtreeIfNeeded()
        #expect(view.label.frame.minX == UpdateRowView.titleX)
    }

    /// The label at `width`, laid out for a title like `title` (its weight and whether the bar follows), fits the
    /// title as its cell draws it, padding included, so nothing is truncated.
    private static func labelFits(_ title: UpdateRowView.Title, width: CGFloat) -> Bool {
        let like: MenuUpdateRowState.Phase = switch (title.isProminent, title.showsProgressBar) {
        case (true, true): .update(.downloading(version, progress: nil))
        case (true, false): .update(.available(version))
        case (false, _): .idle
        }
        let view = UpdateRowView(state: state(like), width: width)
        view.label.stringValue = title.text
        view.layoutSubtreeIfNeeded()
        let needed = view.label.cell?.cellSize.width ?? .infinity
        return view.label.frame.width >= needed
    }

    /// The Turkish titles of every state, from the Turkish strings file, with a version as wide as the widest sample.
    private static func turkishTitles() throws -> [UpdateRowView.Title] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Trrek/Resources/tr.lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
        typealias Title = UpdateRowView.Title
        let keys: [Title] = [
            Title(text: "Check for Updates", isProminent: false, showsProgressBar: false),
            Title(text: "Checking for Updates…", isProminent: false, showsProgressBar: false),
            Title(text: "trrek Is Up to Date", isProminent: false, showsProgressBar: false),
            Title(text: "Couldn’t Check — Try Again", isProminent: false, showsProgressBar: false),
            Title(text: "Update Available: trrek %@", isProminent: true, showsProgressBar: false),
            Title(text: "Downloading trrek %@…", isProminent: true, showsProgressBar: true),
            Title(text: "Installing trrek %@…", isProminent: true, showsProgressBar: true),
            Title(text: "Update Failed — Try Again", isProminent: true, showsProgressBar: false),
            Title(text: "Update in Browser…", isProminent: true, showsProgressBar: false),
            Title(text: "Relaunch to Finish Updating", isProminent: true, showsProgressBar: false)
        ]
        let version = MenuUpdateRowState.widestVersion.description
        return try keys.map { key in
            var title = key
            title.text = try #require(table[key.text], "\(key.text)").replacingOccurrences(of: "%@", with: version)
            return title
        }
    }

    /// Every state's title fits the row without truncation, in English and in Turkish, for the version the row shows,
    /// the known update and the widest likely one.
    @Test func everyTitleFitsTheRow() throws {
        let shown = SemanticVersion(major: 123, minor: 0, patch: 0)
        let known = SemanticVersion(major: 10, minor: 12, patch: 14)
        let english = MenuUpdateRowState.widthSamples(known: [shown, known]).map(UpdateRowView.Title.init)
        let turkish = try Self.turkishTitles()
        #expect(turkish.contains { $0.text == "Güncellemeyi Bitirmek İçin Yeniden Başlat" })
        for titles in [english, turkish] {
            let width = UpdateRowView.width(for: titles)
            for title in titles {
                #expect(Self.labelFits(title, width: width), "\(title.text)")
            }
        }
        let view = UpdateRowView(state: MenuUpdateRowState(), width: 300)
        #expect(view.frame.width == 300)
        #expect(view.autoresizingMask.contains(.width))
    }

    /// A click acts in the view and does not send the item's action (which would close the menu); while the row is
    /// not clickable it does nothing.
    @Test func aClickActsWithoutChoosingTheItem() throws {
        let view = Self.makeView()
        let target = Target()
        let item = NSMenuItem(title: "", action: #selector(Target.chosen), keyEquivalent: "")
        item.target = target
        item.view = view
        var clicks = 0
        view.onClick = { clicks += 1 }

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        view.mouseUp(with: event)
        #expect(clicks == 1)
        #expect(target.sent == 0)

        view.state = Self.state(.checking)
        view.mouseUp(with: event)
        #expect(clicks == 1)

        view.state = Self.state(.upToDate)
        view.mouseUp(with: event)
        #expect(clicks == 1)

        view.state = Self.state(.update(.downloading(Self.version, progress: 0.1)))
        view.mouseUp(with: event)
        #expect(clicks == 1)

        view.state = Self.state(.update(.failed(Self.version)))
        #expect(view.accessibilityPerformPress())
        #expect(clicks == 2)
    }

    /// The selection is drawn only for a highlighted row a click would act on; outside an open menu nothing is.
    @Test func theHighlightFollowsTheMenuAndTheState() {
        #expect(UpdateRowView.showsHighlight(itemHighlighted: true, clickable: true))
        #expect(!UpdateRowView.showsHighlight(itemHighlighted: true, clickable: false))
        #expect(!UpdateRowView.showsHighlight(itemHighlighted: false, clickable: true))
        let view = Self.makeView()
        #expect(!view.isHighlighted)
    }

    @Test func accessibilityFollowsTheState() {
        let view = Self.makeView()
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        #expect(view.isAccessibilityEnabled())
        view.state = Self.state(.checking)
        #expect(!view.isAccessibilityEnabled())
        #expect(!view.accessibilityPerformPress())
        #expect(item.title == "Checking for Updates…")
        view.state = Self.state(.update(.downloading(Self.version, progress: 0.2)))
        #expect(!view.isAccessibilityEnabled())
        #expect(item.title == "Downloading trrek 0.4.0…")
        view.state = Self.state(.update(.failed(Self.version)))
        #expect(view.isAccessibilityEnabled())
        #expect(item.title == "Update Failed — Try Again")
    }
}

/// The menu's update items, updated in place while the menu is open.
@MainActor
struct UpdateMenuItemsTests {
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    private final class Target: NSObject {
        @objc func chosen() {}
    }

    /// A manual check, then an update found by an automatic check, both in the same row view: the menu is never
    /// rebuilt for them.
    @Test func theRowChangesInPlace() throws {
        let items = UpdateMenuItems()
        let target = Target()
        let item = items.makeRowItem(known: [], target: target, action: #selector(Target.chosen)) {}
        let view = try #require(item.view as? UpdateRowView)
        #expect(items.row === view)
        #expect(item.target === target)
        #expect(item.title == "Check for Updates")

        #expect(items.click() == .check)
        #expect(view.state.phase == .checking)
        #expect(!item.isEnabled)
        // The check's start and end reach the row as controller changes; it stays checking until it finishes.
        items.show(update: nil)
        #expect(view.state.phase == .checking)
        items.finishCheck(.upToDate, update: nil)
        #expect(view.state.phase == .upToDate)
        #expect(item.title == "trrek Is Up to Date")

        items.menuClosed()
        #expect(view.state.phase == .idle)

        // An automatic check finds an update while the menu is open; meanwhile the idle row stays clickable.
        items.show(update: nil)
        #expect(item.isEnabled)
        #expect(view.state.phase == .idle)
        items.show(update: .available(Self.version))
        #expect(view.state.phase == .update(.available(Self.version)))
        #expect(item.isEnabled)
        #expect(items.click() == .update)
        items.show(update: .downloading(Self.version, progress: 0.3))
        #expect(view.state.phase == .update(.downloading(Self.version, progress: 0.3)))
        #expect(!item.isEnabled)

        // The state outlives the menu's items.
        items.reset()
        #expect(items.row == nil)
        #expect(items.state.phase == .update(.downloading(Self.version, progress: 0.3)))
    }

    @Test func quitFollowsTheUpdate() {
        let items = UpdateMenuItems()
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        items.track(quit: quit)
        #expect(quit.isEnabled)

        items.show(update: .downloading(Self.version, progress: nil))
        #expect(quit.isEnabled)

        items.show(update: .installing(Self.version))
        #expect(!quit.isEnabled)

        items.show(update: .failed(Self.version))
        #expect(quit.isEnabled)

        // No update known.
        items.show(update: nil)
        #expect(quit.isEnabled)
    }
}
