import AppKit
import Foundation
import Testing
@testable import Trrek

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
