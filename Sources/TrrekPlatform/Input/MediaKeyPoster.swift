import AppKit

/// System media key codes carried in system-defined events.
public enum MediaKey: Int32, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
    case illuminationUp = 21
    case illuminationDown = 22
}

public enum MediaKeyPoster {
    /// Posts a media key press. `fine` adds Option+Shift for quarter-step adjustments.
    public static func post(_ key: MediaKey, fine: Bool) {
        let flags: NSEvent.ModifierFlags = fine ? [.option, .shift] : []
        for state in [0x0A, 0x0B] {
            let data1 = Int((key.rawValue << 16) | Int32(state << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cgEvent = event.cgEvent else { continue }
            EventStamp.stampAndPost(cgEvent)
        }
    }
}
