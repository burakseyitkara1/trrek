import Foundation

/// Settings files opened from Finder, held until the app has finished launching.
///
/// A double-click that launches trrek delivers the file before `applicationDidFinishLaunching`, when nothing can
/// show it yet. Only one import can be confirmed at a time, so of several files the last one is offered.
public struct OpenedFileQueue: Sendable {
    private var pending: [URL]? = []

    public init() {}

    /// Takes newly opened files; returns the one to offer now, or `nil` while launching (it is kept) or when none of
    /// them is a settings file.
    public mutating func receive(_ urls: [URL]) -> URL? {
        let settingsFiles = urls.filter(SettingsDocument.isSettingsFile)
        guard pending != nil else { return settingsFiles.last }
        pending?.append(contentsOf: settingsFiles)
        return nil
    }

    /// Marks launch as finished and returns the file to offer, if any arrived before. Later files are offered as
    /// they arrive.
    public mutating func finishLaunching() -> URL? {
        let last = pending?.last
        pending = nil
        return last
    }
}
