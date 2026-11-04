import AppKit
import Testing
@testable import Trrek

/// The overlay draws only the latest of the values that arrive before the main thread catches up, and hides and
/// releases its panel after the delay that the last update started.
@MainActor
struct OverlayPanelTests {
    @Test func coalescesShowsFromAnotherThread() async throws {
        _ = NSApplication.shared
        let overlay = OverlayPanel(hideDelay: 1)

        showFromAnotherThread(overlay, values: [
            .init(kind: .keyboardBacklight, level: 0.25, label: nil),
            .init(kind: .keyboardBacklight, level: 0.5, label: nil),
            .init(kind: .scrub, level: 0.75, label: "1:05")
        ])
        // Nothing is drawn until the main queue runs the one update the three calls scheduled.
        #expect(overlay.displayed == nil)

        try await waitUntil { overlay.displayed != nil }
        #expect(overlay.displayed == OverlayPanel.Value(kind: .scrub, level: 0.75, label: "1:05"))
        #expect(overlay.isVisible)

        try await waitUntil { !overlay.isVisible }
        #expect(!overlay.isVisible)
        #expect(overlay.displayed == nil)
        #expect(overlay.hideDeadline == nil)
    }

    @Test func laterShowPushesHideBack() async throws {
        _ = NSApplication.shared
        let overlay = OverlayPanel(hideDelay: 1)

        overlay.show(kind: .keyboardBacklight, level: 0.25, label: nil)
        try await waitUntil { overlay.displayed != nil }
        let firstDeadline = try #require(overlay.hideDeadline)

        try await Task.sleep(for: .milliseconds(50))
        overlay.show(kind: .keyboardBacklight, level: 0.5, label: nil)
        try await waitUntil { overlay.displayed?.level == 0.5 }
        let secondDeadline = try #require(overlay.hideDeadline)
        #expect(secondDeadline > firstDeadline)
        #expect(overlay.isVisible)

        try await waitUntil { !overlay.isVisible }
        #expect(!overlay.isVisible)
    }

    @Test func originIsTopRightOfVisibleArea() throws {
        let screen = try #require(NSScreen.main)
        let origin = OverlayPanel.origin(on: screen)
        #expect(origin.x == screen.visibleFrame.maxX - 16 - 220)
        #expect(origin.y == screen.visibleFrame.maxY - 16 - 56)
    }

    /// Calls `show` for each value on a separate thread, as the frame thread does, while the main thread waits
    /// here: the scheduled update cannot run before every call has been made.
    private func showFromAnotherThread(_ overlay: OverlayPanel, values: [OverlayPanel.Value]) {
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            for value in values {
                overlay.show(kind: value.kind, level: value.level, label: value.label)
            }
            finished.signal()
        }
        thread.start()
        finished.wait()
    }
}
