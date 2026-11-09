import AppKit
import Foundation
import Testing
@testable import Trrek
import TrrekAppCore

/// The menu row's view: its texts, progress bar, enabled state and click handling.
@MainActor
struct UpdateRowViewTests {
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    private final class Target: NSObject {
        var sent = 0

        @objc func chosen() {
            sent += 1
        }
    }

    @Test func statesUpdateTitleAndProgressInPlace() {
        let ver = Self.version
        let view = UpdateRowView(state: .available(ver))
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        let height = view.frame.height
        view.layoutSubtreeIfNeeded()

        #expect(view.label.stringValue == "Update Available: trrek 0.4.0")
        #expect(view.accessibilityLabel() == "Update Available: trrek 0.4.0")
        #expect(view.accessibilityRole() == .menuItem)
        #expect(view.bar.isHidden)

        view.state = .downloading(ver, progress: nil)
        #expect(view.label.stringValue == "Downloading trrek 0.4.0…")
        #expect(!view.bar.isHidden && view.bar.isIndeterminate)
        #expect(!item.isEnabled)

        view.state = .downloading(ver, progress: 0.42)
        #expect(!view.bar.isIndeterminate)
        #expect(view.bar.doubleValue == 0.42)
        #expect(view.accessibilityValue() as? String == 0.42.formatted(.percent.precision(.fractionLength(0))))
        view.layoutSubtreeIfNeeded()
        #expect(view.label.frame.maxX <= view.bar.frame.minX)

        view.state = .installing(ver)
        #expect(view.label.stringValue == "Installing trrek 0.4.0…")
        #expect(!view.bar.isHidden && view.bar.isIndeterminate)

        view.state = .failed(ver)
        #expect(view.label.stringValue == "Update Failed — Try Again")
        #expect(view.bar.isHidden)
        #expect(item.isEnabled)
        #expect(view.toolTip == nil)

        // The row stays short; the reason is in the tooltip and read out after the title.
        view.state = .failed(ver, reason: .serverUnavailable)
        #expect(view.label.stringValue == "Update Failed — Try Again")
        #expect(view.toolTip == "GitHub isn’t responding. Try again in a few minutes.")
        #expect(view.accessibilityLabel()
            == "Update Failed — Try Again. GitHub isn’t responding. Try again in a few minutes.")

        // One height in every state, so the open menu keeps its layout.
        #expect(view.frame.height == height)
        #expect(height == UpdateRowView.height)
    }

    @Test func theRowIsWideEnoughForEveryTitle() {
        let view = UpdateRowView(state: .available(Self.version))
        let font = view.label.font ?? NSFont.menuFont(ofSize: 0)
        for state in [UpdateRowState.relaunch(Self.version), .downloading(Self.version, progress: nil)] {
            let width = (state.title as NSString).size(withAttributes: [.font: font]).width
            #expect(view.frame.width > width + 72)
        }
        #expect(view.autoresizingMask.contains(.width))
    }

    /// A click acts in the view and does not send the item's action (which would close the menu); while busy it does
    /// nothing.
    @Test func aClickActsWithoutChoosingTheItem() throws {
        let view = UpdateRowView(state: .available(Self.version))
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

        view.state = .downloading(Self.version, progress: 0.1)
        view.mouseUp(with: event)
        #expect(clicks == 1)

        view.state = .failed(Self.version)
        #expect(view.accessibilityPerformPress())
        #expect(clicks == 2)
    }

    /// The selection is drawn only for a highlighted row a click would act on; outside an open menu nothing is.
    @Test func theHighlightFollowsTheMenuAndTheState() {
        #expect(UpdateRowView.showsHighlight(itemHighlighted: true, clickable: true))
        #expect(!UpdateRowView.showsHighlight(itemHighlighted: true, clickable: false))
        #expect(!UpdateRowView.showsHighlight(itemHighlighted: false, clickable: true))
        let view = UpdateRowView(state: .available(Self.version))
        #expect(!view.isHighlighted)
    }

    @Test func accessibilityFollowsTheState() {
        let view = UpdateRowView(state: .available(Self.version))
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = view
        view.state = .downloading(Self.version, progress: 0.2)
        #expect(!view.isAccessibilityEnabled())
        #expect(!view.accessibilityPerformPress())
        #expect(item.title == "Downloading trrek 0.4.0…")
        view.state = .failed(Self.version)
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

    @Test func theRowUpdatesInPlaceAndOnlyItsAppearanceNeedsARebuild() {
        let items = UpdateMenuItems()
        let target = Target()
        #expect(!items.show(row: nil, isBusy: false))
        #expect(items.show(row: .available(Self.version), isBusy: false))

        let item = items.makeRowItem(.available(Self.version), target: target, action: #selector(Target.chosen)) {}
        let view = try? #require(item.view as? UpdateRowView)
        #expect(items.row === view)
        #expect(item.target === target)
        #expect(!items.show(row: .downloading(Self.version, progress: 0.3), isBusy: true))
        #expect(view?.state == .downloading(Self.version, progress: 0.3))
        #expect(!item.isEnabled)
        #expect(items.show(row: nil, isBusy: false))

        items.reset()
        #expect(items.row == nil)
    }

    @Test func checkAndQuitFollowTheUpdate() {
        let items = UpdateMenuItems()
        let check = NSMenuItem(title: "Check", action: nil, keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        items.track(check: check, quit: quit, row: .available(Self.version), isBusy: false)
        #expect(check.isEnabled && quit.isEnabled)

        _ = items.show(row: .downloading(Self.version, progress: nil), isBusy: true)
        #expect(!check.isEnabled)
        #expect(quit.isEnabled)

        _ = items.show(row: .installing(Self.version), isBusy: true)
        #expect(!check.isEnabled)
        #expect(!quit.isEnabled)

        _ = items.show(row: .failed(Self.version), isBusy: false)
        #expect(check.isEnabled && quit.isEnabled)

        // A check running with no update known.
        _ = items.show(row: nil, isBusy: true)
        #expect(!check.isEnabled)
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
