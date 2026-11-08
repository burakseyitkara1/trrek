import AppKit

/// The menu bar icon, drawn in code as a template image: a trackpad outline with its right edge highlighted, plus a
/// dot in the bottom-right corner while a toggled hold key is on, a dot in the top-right corner while Accessibility
/// access is missing, and a filled up-arrow in the top-left corner while an update is known. Each mark is cut out of
/// the outline with a 1 pt clear ring, so it stays legible in light and dark menu bars.
enum MenuIcon {
    static let size = NSSize(width: 18, height: 18)

    /// What the icon shows.
    struct State: Equatable {
        /// A toggled hold key is on.
        var active = false
        /// Accessibility access is missing.
        var attention = false
        /// A newer version is known.
        var update = false
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(state)
        return image
    }

    /// What VoiceOver reads for the icon: "trrek", followed by the states that hold, in parentheses.
    static func description(_ state: State) -> String {
        var parts: [String] = []
        if state.update {
            parts.append(String(localized: "update available", bundle: .main))
        }
        if state.attention {
            parts.append(String(localized: "Accessibility access needed", bundle: .main))
        }
        if state.active {
            parts.append(String(localized: "hold-to-slide on", bundle: .main))
        }
        guard !parts.isEmpty else { return "trrek" }
        let list = parts.joined(separator: ", ")
        return String(localized: "trrek (\(list))", bundle: .main)
    }

    private static func draw(_ state: State) {
        NSColor.black.set()

        let outline = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11),
            xRadius: 2.5,
            yRadius: 2.5
        )
        outline.lineWidth = 1
        outline.stroke()

        NSBezierPath(roundedRect: NSRect(x: 13, y: 5, width: 2, height: 8), xRadius: 1, yRadius: 1).fill()

        if state.active {
            mark(NSBezierPath(ovalIn: NSRect(x: 14, y: 0, width: 4, height: 4)))
        }
        if state.attention {
            mark(NSBezierPath(ovalIn: NSRect(x: 13.5, y: 13.5, width: 4.5, height: 4.5)))
        }
        if state.update {
            mark(updateArrow)
        }
    }

    /// A filled up-arrow in the top-left corner (head 6 pt wide, 3.5 pt tall, on a 2 pt stem): a shape that reads
    /// differently from the round dots of the other marks.
    static var updateArrow: NSBezierPath {
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 3.5, y: 18))
        arrow.line(to: NSPoint(x: 6.5, y: 14.5))
        arrow.line(to: NSPoint(x: 4.5, y: 14.5))
        arrow.line(to: NSPoint(x: 4.5, y: 11))
        arrow.line(to: NSPoint(x: 2.5, y: 11))
        arrow.line(to: NSPoint(x: 2.5, y: 14.5))
        arrow.line(to: NSPoint(x: 0.5, y: 14.5))
        arrow.close()
        return arrow
    }

    /// Fills `shape` after clearing a 1 pt ring around it, so it reads as a badge over the outline.
    private static func mark(_ shape: NSBezierPath) {
        guard let context = NSGraphicsContext.current else { return }
        context.compositingOperation = .clear
        let ring = shape.copy() as? NSBezierPath ?? shape
        ring.lineWidth = 2
        ring.lineJoinStyle = .round
        ring.stroke()
        ring.fill()
        context.compositingOperation = .sourceOver
        shape.fill()
    }
}
