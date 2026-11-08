import Foundation

/// Command-line options the app understands at launch.
///
/// - `--settings [tab]` opens the settings window, optionally on a tab.
/// - `--welcome` opens the welcome window.
/// - `--demo-overlay` shows the level overlay once.
/// - `--quit-after <seconds>` quits after the given time (for screenshots and footprint checks).
/// - `--skip-first-run` records the welcome window as shown and shows no welcome window at launch, neither the
///   first-run one nor the one for missing Accessibility (for screenshots and footprint checks).
/// - `--assume-version X.Y.Z` makes the update check treat the running version as X.Y.Z, to try the update flow
///   against the real feed. Nothing else sees it; the installer still refuses a version older than the running one.
public struct LaunchOptions: Equatable, Sendable {
    public var openSettings = false
    /// The tab to open settings on; `nil` for the default tab.
    public var settingsTab: String?
    public var welcome = false
    public var demoOverlay = false
    public var quitAfter: TimeInterval?
    public var skipFirstRun = false
    /// The version the update check compares with the feed instead of the running one.
    public var assumedVersion: SemanticVersion?

    public init() {}

    /// Parses `arguments` as in `CommandLine.arguments`; the first element is the executable and is skipped.
    /// Unknown arguments are ignored.
    public init(arguments: [String]) {
        var remaining = arguments.dropFirst()[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--settings":
                openSettings = true
                if let tab = remaining.first, !tab.hasPrefix("--") {
                    settingsTab = tab
                    remaining.removeFirst()
                }
            case "--welcome":
                welcome = true
            case "--demo-overlay":
                demoOverlay = true
            case "--skip-first-run":
                skipFirstRun = true
            case "--assume-version":
                assumedVersion = Self.takeValue(from: &remaining, SemanticVersion.init)
            case "--quit-after":
                quitAfter = Self.takeValue(from: &remaining) { TimeInterval($0).flatMap { $0 >= 0 ? $0 : nil } }
            default:
                break
            }
        }
    }

    /// The next argument parsed by `parse`, which is then consumed; `nil` (and nothing consumed) when it is missing
    /// or does not parse.
    private static func takeValue<T>(
        from remaining: inout ArraySlice<String>,
        _ parse: (String) -> T?
    ) -> T? {
        guard let value = remaining.first.flatMap(parse) else { return nil }
        remaining.removeFirst()
        return value
    }
}
