import CoreGraphics
import Foundation
import Synchronization

/// HID-level event tap that can freeze the cursor by swallowing pointer movement and scroll events before
/// they reach the window server. Starts disabled; it only sees events while frozen. Events stamped by trrek
/// pass through.
///
/// The tap's run-loop source lives on the main run loop, so the object is created on the main actor and the
/// tap callback runs on the main thread. `tap` and `isAvailable` are only written during `init`.
/// `setFreeze` may be called from any thread.
public final class EventTapGuard: CursorFreezing, @unchecked Sendable {
    public private(set) var isAvailable = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let frozen = Atomic<Bool>(false)

    @MainActor
    public init() {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            platformLogger.error("event tap unavailable (accessibility not granted)")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        runLoopSource = source
        isAvailable = true
    }

    deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    /// While frozen, pointer movement and scroll events from the user are swallowed.
    /// Safe from any thread: enabling or disabling a tap is thread-safe.
    public func setFreeze(_ on: Bool) {
        frozen.store(on, ordering: .releasing)
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: on)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let isFrozen = frozen.load(ordering: .acquiring)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isFrozen, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if EventStamp.isOurs(event) || !isFrozen {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<EventTapGuard>.fromOpaque(userInfo).takeUnretainedValue()
    return owner.handle(type, event)
}
