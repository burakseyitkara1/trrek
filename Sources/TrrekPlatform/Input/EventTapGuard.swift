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
    private let anchor = Mutex<CGPoint?>(nil)

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
        if frozen.load(ordering: .acquiring) {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    /// While frozen, the cursor stays where it was and scroll events from the user are swallowed.
    /// Swallowing pointer events alone does not stop the cursor (its position is updated before taps see the
    /// event), so freezing also disconnects mouse movement from the cursor and remembers the position to restore
    /// it if anything still moves it. Safe from any thread: these calls and enabling a tap are thread-safe.
    public func setFreeze(_ on: Bool) {
        let wasFrozen = frozen.exchange(on, ordering: .acquiringAndReleasing)
        guard let tap else { return }
        if on, !wasFrozen {
            anchor.withLock { $0 = CGEvent(source: nil)?.location }
            CGAssociateMouseAndMouseCursorPosition(0)
        } else if !on, wasFrozen {
            CGAssociateMouseAndMouseCursorPosition(1)
            anchor.withLock { $0 = nil }
        }
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
        if type != .scrollWheel, let point = anchor.withLock({ $0 }) {
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(0)
        }
        return nil
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<EventTapGuard>.fromOpaque(userInfo).takeUnretainedValue()
    return owner.handle(type, event)
}
