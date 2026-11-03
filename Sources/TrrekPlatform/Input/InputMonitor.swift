import CoreGraphics
import Foundation

/// Session-level, listen-only event tap that reports key presses and modifier changes from the user.
/// Events stamped by trrek are ignored.
///
/// The tap's run-loop source lives on the main run loop, so the object is created and started on the main
/// actor and the callbacks run synchronously on the main thread. The tap is created in `init` and again in
/// `start()` when it is still missing, so starting after Accessibility is granted works without a new object.
public final class InputMonitor {
    /// `false` while Accessibility is not granted or the tap could not be created.
    public private(set) var isAvailable = false

    /// Called for every key-down event. The argument is the event time in seconds of system uptime; convert
    /// it with `GesturePipeline.engineTime(fromUptime:)` before handing it to the engine.
    public var onKeyDown: (@Sendable (TimeInterval) -> Void)?

    /// Called for every modifier change with the event's full flags and its time in seconds of system uptime
    /// (see `onKeyDown`).
    public var onFlagsChanged: (@Sendable (CGEventFlags, TimeInterval) -> Void)?

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
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
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

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isRunning, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .keyDown:
            guard !EventStamp.isOurs(event) else { return }
            onKeyDown?(Self.seconds(event))
        case .flagsChanged:
            guard !EventStamp.isOurs(event) else { return }
            onFlagsChanged?(event.flags, Self.seconds(event))
        default:
            break
        }
    }

    private static func seconds(_ event: CGEvent) -> TimeInterval {
        Double(event.timestamp) / 1e9
    }
}

private let inputTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo {
        Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}
