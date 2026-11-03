@preconcurrency import ApplicationServices
import Foundation
import Synchronization

/// Accessibility trust, required for event taps and for posted events to be delivered.
public enum Permissions {
    private struct Observation {
        var onChange: (@Sendable (Bool) -> Void)?
        var lastValue: Bool?
        var observer: (any NSObjectProtocol)?
    }

    private static let observation = Mutex(Observation())

    /// The system posts this whenever an application's Accessibility trust changes.
    private static let trustChanged = Notification.Name("com.apple.accessibility.api")

    /// The trust database can lag behind the notification, so trust is read again once after this delay.
    private static let recheckDelay: TimeInterval = 0.5

    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Called on the main thread with the new trust value whenever it changes while observing.
    public static var onChange: (@Sendable (Bool) -> Void)? {
        get { observation.withLock { $0.onChange } }
        set { observation.withLock { $0.onChange = newValue } }
    }

    /// Shows the system prompt that leads the user to the Accessibility settings.
    public static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Starts watching for Accessibility trust changes; `onChange` fires only when the value differs from the
    /// last one seen. Calling it again while observing does nothing.
    public static func startObserving() {
        observation.withLock { state in
            guard state.observer == nil else { return }
            state.lastValue = AXIsProcessTrusted()
            state.observer = DistributedNotificationCenter.default().addObserver(
                forName: trustChanged,
                object: nil,
                queue: .main
            ) { _ in
                evaluate()
                DispatchQueue.main.asyncAfter(deadline: .now() + recheckDelay) { evaluate() }
            }
        }
    }

    private static func evaluate() {
        let trusted = AXIsProcessTrusted()
        let callback: (@Sendable (Bool) -> Void)? = observation.withLock { state in
            guard state.lastValue != trusted else { return nil }
            state.lastValue = trusted
            return state.onChange
        }
        callback?(trusted)
    }
}
