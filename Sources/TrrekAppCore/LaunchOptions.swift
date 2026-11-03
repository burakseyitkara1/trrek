import Foundation

/// Command-line options the app understands at launch.
///
/// - `--settings [tab]` opens the settings window, optionally on a tab.
/// - `--welcome` opens the welcome window.
/// - `--demo-overlay` shows the level overlay once.
/// - `--quit-after <seconds>` quits after the given time (for screenshots and footprint checks).
public struct LaunchOptions: Equatable, Sendable {
    public var openSettings = false
    /// The tab to open settings on; `nil` for the default tab.
    public var settingsTab: String?
    public var welcome = false
    public var demoOverlay = false
    public var quitAfter: TimeInterval?

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
            case "--quit-after":
                if let value = remaining.first.flatMap(TimeInterval.init), value >= 0 {
                    quitAfter = value
                    remaining.removeFirst()
                }
            default:
                break
            }
        }
    }
}
