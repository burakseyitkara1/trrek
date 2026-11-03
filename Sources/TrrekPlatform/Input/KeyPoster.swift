import CoreGraphics

/// Posts synthetic keyboard events stamped as trrek's own.
public enum KeyPoster {
    public static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        post(keyCode, down: true, flags: flags)
        post(keyCode, down: false, flags: flags)
    }

    public static func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        post(keyCode, down: true, flags: flags)
    }

    public static func modifierUp(_ keyCode: CGKeyCode) {
        post(keyCode, down: false, flags: [])
    }

    private static func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: EventStamp.source, virtualKey: keyCode, keyDown: down) else {
            return
        }
        event.flags = flags
        EventStamp.stampAndPost(event)
    }
}
