import CoreFoundation
import IOKit

/// Reports when a multitouch device is attached or removed.
///
/// The notification port's run-loop source lives on the main run loop, so `onChange` is called on the main
/// thread. Configure, start and stop it on the main thread.
public final class DeviceHotplugObserver {
    public var onChange: (@Sendable () -> Void)?

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOMatchedNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), hotplugCallback, context, &iterator
            )
            guard result == KERN_SUCCESS else {
                platformLogger.error("device notification failed: \(result, privacy: .public)")
                continue
            }
            iterators.append(iterator)
            // Draining arms the notification; the devices already present are not a change.
            Self.drain(iterator)
        }
    }

    public func stop() {
        for iterator in iterators {
            IOObjectRelease(iterator)
        }
        iterators.removeAll()
        guard let port else { return }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        IONotificationPortDestroy(port)
        self.port = nil
    }

    fileprivate func handle(_ iterator: io_iterator_t) {
        Self.drain(iterator)
        onChange?()
    }

    private static func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

private let hotplugCallback: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<DeviceHotplugObserver>.fromOpaque(context).takeUnretainedValue().handle(iterator)
}
