import AppKit

/// Reports the application that becomes frontmost: its bundle ID and whether it is this process.
///
/// Configure, start and stop it on the main thread; `onChange` is called on the main thread.
public final class FrontmostObserver: @unchecked Sendable {
    /// Called with the activated application's bundle ID (`nil` when it has none) and whether it is this process.
    public var onChange: (@Sendable (_ bundleID: String?, _ isOwnApp: Bool) -> Void)?

    private var observer: (any NSObjectProtocol)?

    /// The bundle ID of the current frontmost application.
    public static var currentBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Whether this process is the frontmost application.
    public static var isOwnAppFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication.map(isOwnApp) ?? false
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
            self?.onChange?(app?.bundleIdentifier, app.map(Self.isOwnApp) ?? false)
        }
    }

    private static func isOwnApp(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    public func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
