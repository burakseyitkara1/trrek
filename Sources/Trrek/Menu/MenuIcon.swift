import AppKit

/// The menu bar icon, drawn in code: a trackpad outline with its right edge highlighted, plus a dot in the
/// bottom-right corner while a toggled hold key is on.
enum MenuIcon {
    private static let size = NSSize(width: 18, height: 18)

    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(active: active)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "trrek (hold-to-slide on)" : "trrek"
        return image
    }

    private static func draw(active: Bool) {
        NSColor.black.set()

        let outline = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11),
            xRadius: 2.5,
            yRadius: 2.5
        )
        outline.lineWidth = 1
        outline.stroke()

        NSBezierPath(roundedRect: NSRect(x: 13, y: 5, width: 2, height: 8), xRadius: 1, yRadius: 1).fill()

        guard active, let context = NSGraphicsContext.current else { return }
        let dot = NSRect(x: 14, y: 0, width: 4, height: 4)
        // Clear a 1 pt ring around the dot so it reads as a badge over the outline's corner.
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
        context.compositingOperation = .sourceOver
        NSBezierPath(ovalIn: dot).fill()
    }
}
