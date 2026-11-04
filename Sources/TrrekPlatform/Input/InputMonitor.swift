import CoreGraphics
import Foundation

/// Session-level, listen-only event tap that reports key presses, modifier changes and mouse button presses from
/// the user. Events stamped by trrek are ignored.
///
/// Times are arrival times: the system uptime read inside the tap callback, in seconds
/// (`ProcessInfo.processInfo.systemUptime`). The event's own timestamp is not used, since its clock is not
/// documented; it is kept in `lastEventTimestamp` for diagnostics only.
///
/// The tap's run-loop source lives on the main run loop, so the object is created and started on the main
/// actor and the callbacks run synchronously on the main thread. The tap is created in `init` and again in
/// `start()` when it is still missing, so starting after Accessibility is granted works without a new object.
public final class InputMonitor {
    /// `false` while Accessibility is not granted or the tap could not be created.
    public private(set) var isAvailable = false

    /// Called for every key-down event with its arrival time in seconds of system uptime; convert it with
    /// `GesturePipeline.engineTime(fromUptime:)` before handing it to the engine.
    public var onKeyDown: (@Sendable (TimeInterval) -> Void)?

    /// Called for every modifier change with the event's full flags and its arrival time (see `onKeyDown`).
    public var onFlagsChanged: (@Sendable (CGEventFlags, TimeInterval) -> Void)?

    /// Called for every left, right or other mouse button press with its arrival time (see `onKeyDown`).
    public var onMouseDown: (@Sendable (TimeInterval) -> Void)?

    /// The timestamp the most recent reported event carries, converted to seconds; for diagnostics only.
    public private(set) var lastEventTimestamp: TimeInterval = 0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    @MainActor
    public init() {
        createTap()
    }

    deinit {
        removeTap()
    }

    /// Starts reporting events; creates the tap first if it is missing.
    @MainActor
    public func start() {
        if tap == nil {
            createTap()
        }
        guard let tap else { return }
        isRunning = true
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Stops reporting events. The tap stays installed, disabled, until the object is released.
    @MainActor
    public func stop() {
        isRunning = false
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
    }

    private func createTap() {
        // A listen-only session tap can be created without permission and then silently receives nothing,
        // so creation is gated on the permission instead of on the tap alone.
        guard Permissions.isTrusted || CGPreflightListenEventAccess() else {
            platformLogger.error("input monitor unavailable (accessibility not granted)")
            isAvailable = false
            return
        }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: inputTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            platformLogger.error("input monitor tap could not be created")
            isAvailable = false
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        runLoopSource = source
        isAvailable = true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// `arrival` is the system uptime read when the callback started.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent, arrival: TimeInterval) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isRunning, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .keyDown:
            guard !EventStamp.isOurs(event) else { return }
            lastEventTimestamp = Double(event.timestamp) / 1e9
            onKeyDown?(arrival)
        case .flagsChanged:
            guard !EventStamp.isOurs(event) else { return }
            lastEventTimestamp = Double(event.timestamp) / 1e9
            onFlagsChanged?(event.flags, arrival)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard !EventStamp.isOurs(event) else { return }
            lastEventTimestamp = Double(event.timestamp) / 1e9
            onMouseDown?(arrival)
        default:
            break
        }
    }
}

private let inputTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let arrival = ProcessInfo.processInfo.systemUptime
    if let userInfo {
        Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event, arrival: arrival)
    }
    return Unmanaged.passUnretained(event)
}
