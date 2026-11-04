import AppKit

/// Opens Mission Control views by launching the system Mission Control app with the view's arguments.
///
/// The app is found by its bundle identifier, then at its path under /System/Applications. When it cannot be found
/// or launched the failure is logged and nothing else happens. The lookup and launch run on the main queue, so the
/// frame thread never waits for them.
public struct SystemMissionControl: MissionControlOpening {
    static let bundleIdentifier = "com.apple.exposelauncher"
    static let fallbackPath = "/System/Applications/Mission Control.app"

    public init() {}

    public func open(_ view: MissionControlView) {
        let arguments = view.arguments
        DispatchQueue.main.async {
            guard let url = Self.applicationURL() else {
                platformLogger.error("mission control app not found")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            // A still-running instance would ignore the arguments; each request starts its own short-lived instance.
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    platformLogger.error(
                        "mission control could not be opened: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        }
    }

    /// Where the system Mission Control app is, or `nil` when it is missing.
    static func applicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let fallback = URL(fileURLWithPath: fallbackPath)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }
}
