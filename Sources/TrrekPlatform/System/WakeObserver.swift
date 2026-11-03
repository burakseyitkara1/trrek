import AppKit

/// Reports when the system wakes from sleep.
///
/// Configure, start and stop it on the main thread; `onWake` is called on the main thread.
public final class WakeObserver: @unchecked Sendable {
    public var onWake: (@Sendable () -> Void)?

    private var observer: (any NSObjectProtocol)?

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWake?()
        }
    }

    public func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
