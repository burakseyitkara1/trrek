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
            state.show(update: row, isCheckRunning: false)
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
        UpdateRowView(state: state(phase), width: UpdateRowView.width(for: MenuUpdateRowState.widthSamples(known: nil)))
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
        // Not in a window, so nothing animates.
        #expect(view.bar.isHidden)

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

    /// The row is as wide as its widest state, with the bar after the titles that show it, for the known update and
    /// for one found while the menu is open.
    @Test func theRowIsWideEnoughForEveryState() {
        let known = SemanticVersion(major: 123, minor: 0, patch: 0)
        let samples = MenuUpdateRowState.widthSamples(known: known)
        let width = UpdateRowView.width(for: samples)
        let found = SemanticVersion(major: 10, minor: 12, patch: 14)
        var states = samples
        for row in [UpdateRowState.downloading(found, progress: nil), .relaunch(found), .available(found)] {
            var state = MenuUpdateRowState()
            state.show(update: row, isCheckRunning: false)
            states.append(state)
        }
        for state in states {
            let title = (state.title as NSString).size(withAttributes: [.font: UpdateRowView.font(for: state)]).width
            let needed = UpdateRowView.titleX + title + (state.showsProgressBar ? UpdateRowView.barWidth : 0)
            #expect(width > needed, "\(state.title)")
        }
        let view = UpdateRowView(state: MenuUpdateRowState(), width: width)
        #expect(view.frame.width == width)
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
        let item = items.makeRowItem(known: nil, target: target, action: #selector(Target.chosen)) {}
        let view = try #require(item.view as? UpdateRowView)
        #expect(items.row === view)
        #expect(item.target === target)
        #expect(item.title == "Check for Updates")

        #expect(items.click() == .check)
        #expect(view.state.phase == .checking)
        #expect(!item.isEnabled)
        // The check's own start and end reach the row as controller changes; it stays checking until it finishes.
        items.show(update: nil, isCheckRunning: true)
        items.show(update: nil, isCheckRunning: false)
        #expect(view.state.phase == .checking)
        items.finishCheck(.upToDate, update: nil)
        #expect(view.state.phase == .upToDate)
        #expect(item.title == "trrek Is Up to Date")

        items.menuClosed()
        #expect(view.state.phase == .idle)

        // An automatic check finds an update while the menu is open.
        items.show(update: nil, isCheckRunning: true)
        #expect(!item.isEnabled)
        #expect(view.state.phase == .idle)
        items.show(update: .available(Self.version), isCheckRunning: false)
        #expect(view.state.phase == .update(.available(Self.version)))
        #expect(item.isEnabled)
        #expect(items.click() == .update)
        items.show(update: .downloading(Self.version, progress: 0.3), isCheckRunning: false)
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

        items.show(update: .downloading(Self.version, progress: nil), isCheckRunning: false)
        #expect(quit.isEnabled)

        items.show(update: .installing(Self.version), isCheckRunning: false)
        #expect(!quit.isEnabled)

        items.show(update: .failed(Self.version), isCheckRunning: false)
        #expect(quit.isEnabled)

        // A check running with no update known.
        items.show(update: nil, isCheckRunning: true)
        #expect(quit.isEnabled)
    }
}

/// The menu bar icon's update badge, rendered offscreen.
@MainActor
struct MenuIconTests {
    /// The alpha of each pixel of the icon rendered at 2x, row 0 at the top.
    private static func alpha(_ state: MenuIcon.State) throws -> [[UInt8]] {
        let side = 36
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = MenuIcon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuIcon.image(state).draw(in: NSRect(origin: .zero, size: MenuIcon.size))
        NSGraphicsContext.restoreGraphicsState()
        return (0 ..< side)
            .map { y in (0 ..< side).map { x in
                UInt8(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
            } }
    }

    /// The number of mostly opaque pixels in each row of a region.
    private static func rowCoverage(_ alpha: [[UInt8]], rows: Range<Int>, columns: Range<Int>) -> [Int] {
        rows.map { y in columns.count { alpha[y][$0] > 128 } }
    }

    @Test func theUpdateBadgeSitsTopLeftAndOnlyChangesThatCorner() throws {
        let plain = try Self.alpha(MenuIcon.State())
        let update = try Self.alpha(MenuIcon.State(update: true))
        var changedTopLeft = 0
        var changedElsewhere = 0
        for y in 0 ..< 36 {
            for x in 0 ..< 36 where plain[y][x] != update[y][x] {
                if x < 16, y < 16 {
                    changedTopLeft += 1
                } else {
                    changedElsewhere += 1
                }
            }
        }
        #expect(changedTopLeft > 40)
        #expect(changedElsewhere == 0)

        // The other marks' corners are untouched by the update badge, and vice versa.
        let all = try Self.alpha(MenuIcon.State(active: true, attention: true, update: true))
        let withoutUpdate = try Self.alpha(MenuIcon.State(active: true, attention: true))
        for y in 0 ..< 36 {
            for x in 18 ..< 36 {
                #expect(all[y][x] == withoutUpdate[y][x])
            }
        }
    }

    /// The badge is an arrow, not a dot: narrow at its tip, widest at the base of its head, then a narrow stem;
    /// the Accessibility dot is symmetric top to bottom.
    @Test func theUpdateBadgeReadsDifferentlyFromTheDots() throws {
        let update = try Self.alpha(MenuIcon.State(update: true))
        let arrow = Self.rowCoverage(update, rows: 0 ..< 14, columns: 0 ..< 14).filter { $0 > 0 }
        let widest = try #require(arrow.max())
        let widestRow = try #require(arrow.firstIndex(of: widest))
        #expect(try #require(arrow.first) < widest)
        #expect(try #require(arrow.last) < widest)
        #expect(widestRow < arrow.count / 2 + 1)

        let attention = try Self.alpha(MenuIcon.State(attention: true))
        let dot = Self.rowCoverage(attention, rows: 0 ..< 10, columns: 26 ..< 36).filter { $0 > 0 }
        #expect(dot == dot.reversed())
    }

    @Test func theIconIsATemplateWithADescription() {
        let image = MenuIcon.image(MenuIcon.State(update: true))
        #expect(image.isTemplate)
        #expect(MenuIcon.description(MenuIcon.State()) == "trrek")
        #expect(MenuIcon.description(MenuIcon.State(update: true)) == "trrek (update available)")
        #expect(MenuIcon.description(MenuIcon.State(active: true, attention: true, update: true))
            == "trrek (update available, Accessibility access needed, hold-to-slide on)")
    }
}
