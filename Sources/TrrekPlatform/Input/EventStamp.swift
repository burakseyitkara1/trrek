import CoreGraphics

/// Marks events posted by trrek so its own taps can recognize and pass them through.
public enum EventStamp {
    public static let userData: Int64 = 0x7472_726B

    public nonisolated(unsafe) static let source: CGEventSource = {
        guard let source = CGEventSource(stateID: .privateState) else {
            fatalError("CGEventSource(stateID: .privateState) is unavailable")
        }
        source.userData = userData
        return source
    }()

    public static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userData
    }

    static func stampAndPost(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: userData)
        event.post(tap: .cghidEventTap)
    }
}
