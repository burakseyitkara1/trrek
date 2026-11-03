import AppKit

/// Reports the bundle ID of the application that becomes frontmost.
///
/// Configure, start and stop it on the main thread; `onChange` is called on the main thread.
public final class FrontmostObserver: @unchecked Sendable {
    /// Called with the activated application's bundle ID (`nil` when it has none).
    public var onChange: (@Sendable (String?) -> Void)?

    private var observer: (any NSObjectProtocol)?

    /// The bundle ID of the current frontmost application.
    public static var currentBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onChange?(app?.bundleIdentifier)
        }
    }

    public func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
