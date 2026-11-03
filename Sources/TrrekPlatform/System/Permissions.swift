@preconcurrency import ApplicationServices

/// Accessibility trust, required for event taps and for posted events to be delivered.
public enum Permissions {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that leads the user to the Accessibility settings.
    public static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
