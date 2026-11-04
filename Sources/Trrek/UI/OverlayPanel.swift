import AppKit
import SwiftUI
import Synchronization
import TrrekAppCore
import TrrekPlatform

/// A transient level indicator near the top-right corner of the screen with the pointer. While it is visible it
/// moves to whichever screen the pointer is on when the next value is drawn.
///
/// `show` is called on the multitouch frame thread while the dispatcher holds its lock, so it only stores the
/// value and schedules one main-thread update without waiting for it. Values that arrive before that update
/// runs replace each other; only the latest is drawn. The panel is built on the first update, hidden and
/// released `hideDelay` after the last one.
@MainActor
final class OverlayPanel: LevelOverlayPresenting {
    static let size = CGSize(width: OverlayLayout.width, height: OverlayLayout.height)
    /// Distance from the top and right edges of the screen's visible area.
    static let inset: CGFloat = 16

    struct Value: Equatable, Sendable {
        var kind: OverlayKind
        var level: Float
        var label: String?
    }

    private struct Pending {
        var value: Value?
        var updateScheduled = false
    }

    private nonisolated let pending = Mutex(Pending())
    private let hideDelay: TimeInterval
    /// Where the panel belongs right now: the top right of the screen with the pointer. Injected by tests.
    private let placement: @MainActor () -> CGPoint
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var hideWork: DispatchWorkItem?
    /// When the pending hide runs; `nil` while hidden.
    private(set) var hideDeadline: DispatchTime?

    /// The value on screen; `nil` while hidden.
    private(set) var displayed: Value?
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// The panel's origin on screen; `nil` while hidden.
    var origin: CGPoint? {
        panel?.frame.origin
    }

    init(
        hideDelay: TimeInterval = 1.0,
        placement: @escaping @MainActor () -> CGPoint = { OverlayPanel.origin(on: OverlayPanel.screenWithPointer()) }
    ) {
        self.hideDelay = hideDelay
        self.placement = placement
    }

    nonisolated func show(kind: OverlayKind, level: Float, label: String?) {
        let value = Value(kind: kind, level: level, label: label)
        let schedule = pending.withLock { state in
            state.value = value
            guard !state.updateScheduled else { return false }
            state.updateScheduled = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Draws the latest pending value and restarts the hide countdown.
    private func update() {
        let value = pending.withLock { state in
            state.updateScheduled = false
            defer { state.value = nil }
            return state.value
        }
        guard let value else { return }
        let view = OverlayView(kind: value.kind, level: value.level, label: value.label)
        let panel = panel ?? makePanel(rootView: view)
        hostingView?.rootView = view
        displayed = value
        // Follows the pointer: a value drawn while the pointer is on another screen moves the panel there.
        let origin = placement()
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        let deadline = DispatchTime.now() + hideDelay
        hideDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    private func hide() {
        hideWork = nil
        hideDeadline = nil
        displayed = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hostingView = nil
    }

    private func makePanel(rootView: OverlayView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    static func screenWithPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }

    /// The panel's origin at the top right of `screen`'s visible area.
    static func origin(on screen: NSScreen?) -> CGPoint {
        guard let area = screen?.visibleFrame else { return .zero }
        return CGPoint(x: area.maxX - inset - size.width, y: area.maxY - inset - size.height)
    }
}
