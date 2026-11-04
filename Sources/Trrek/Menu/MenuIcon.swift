import AppKit

/// The menu bar icon, drawn in code: a trackpad outline with its right edge highlighted, plus a dot in the
/// bottom-right corner while a toggled hold key is on and a dot in the top-right corner while Accessibility access
/// is missing.
enum MenuIcon {
    private static let size = NSSize(width: 18, height: 18)

    static func image(active: Bool, attention: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(active: active, attention: attention)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(active: active, attention: attention)
        return image
    }

    /// What VoiceOver reads for the icon; each state is one phrase, so a translation can word it as a whole.
    private static func description(active: Bool, attention: Bool) -> String {
        switch (attention, active) {
        case (false, false): "trrek"
        case (true, false): String(localized: "trrek (Accessibility access needed)", bundle: .main)
        case (false, true): String(localized: "trrek (hold-to-slide on)", bundle: .main)
        case (true, true): String(localized: "trrek (Accessibility access needed, hold-to-slide on)", bundle: .main)
        }
    }

    private static func draw(active: Bool, attention: Bool) {
        NSColor.black.set()

        let outline = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11),
            xRadius: 2.5,
            yRadius: 2.5
        )
        outline.lineWidth = 1
        outline.stroke()

        NSBezierPath(roundedRect: NSRect(x: 13, y: 5, width: 2, height: 8), xRadius: 1, yRadius: 1).fill()

        if active {
            badge(NSRect(x: 14, y: 0, width: 4, height: 4))
        }
        if attention {
            badge(NSRect(x: 13.5, y: 13.5, width: 4.5, height: 4.5))
        }
    }

    /// A filled dot with a cleared 1 pt ring, so it reads as a badge over the outline's corner.
    private static func badge(_ dot: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
        context.compositingOperation = .sourceOver
        NSBezierPath(ovalIn: dot).fill()
    }
}
