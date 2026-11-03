import CoreGraphics

/// Posts synthetic mouse events stamped as trrek's own.
public enum MousePoster {
    private static let centerButtonNumber: Int64 = 2

    /// Clicks the middle button at the current pointer position.
    public static func middleClick() {
        // An empty event carries the pointer position in global display coordinates (origin top-left).
        let location = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: EventStamp.source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .center
            ) else { continue }
            event.setIntegerValueField(.mouseEventButtonNumber, value: centerButtonNumber)
            EventStamp.stampAndPost(event)
        }
    }
}
