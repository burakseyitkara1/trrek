import CoreGraphics
import Foundation

/// Session event tap that can freeze the cursor by swallowing pointer movement and scroll
/// events. Starts disabled; it only sees events while frozen. Events stamped by trrek pass.
public final class EventTapGuard {
    public private(set) var isAvailable = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var frozen = false

    public init() {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
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
    public func setFreeze(_ on: Bool) {
        frozen = on
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: on)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if frozen, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if EventStamp.isOurs(event) || !frozen {
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
