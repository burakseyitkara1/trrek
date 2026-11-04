import Synchronization
import TrrekEngine

/// Plays each haptic on the trackpad the gesture ran on.
///
/// Holds one actuator per streaming multitouch device, keyed by the engine's device ID
/// (`GesturePipeline.deviceID(of:)`). A haptic for a device without an actuator plays on the built-in trackpad's
/// actuator, and when there is none on `fallback` (the system's generic haptics). `install(devices:makeActuator:)`
/// replaces the table each time the pipeline starts, so a trackpad plugged in or a wake gets fresh actuators.
///
/// Thread-safe: `perform` runs on the frame thread or the dispatcher's display queue, `install` on the main thread.
/// The table lookup does not allocate.
public final class DeviceHaptics: HapticPerforming, @unchecked Sendable {
    private struct Table {
        var actuators: [UInt64: any HapticActuating] = [:]
        var builtIn: (any HapticActuating)?
    }

    private let fallback: any HapticActuating
    private let table = Mutex(Table())

    public init(fallback: any HapticActuating) {
        self.fallback = fallback
    }

    /// Number of devices with an actuator of their own.
    public var actuatorCount: Int {
        table.withLock { $0.actuators.count }
    }

    /// Opens an actuator with `makeActuator` for every device in `devices` that has a multitouch ID, and replaces
    /// the table with them. The previous actuators are released (and closed) after the swap.
    public func install(devices: [MultitouchDeviceInfo], makeActuator: (UInt64) -> (any HapticActuating)?) {
        var newTable = Table()
        for device in devices {
            guard let multitouchID = device.multitouchID, let actuator = makeActuator(multitouchID) else { continue }
            newTable.actuators[GesturePipeline.deviceID(of: device.ref)] = actuator
            if device.isBuiltIn, newTable.builtIn == nil {
                newTable.builtIn = actuator
            }
        }
        table.withLock { swap(&$0, &newTable) }
    }

    public func perform(_ event: HapticEvent, strength: HapticStrength, device: UInt64) {
        let actuator = table.withLock { $0.actuators[device] ?? $0.builtIn } ?? fallback
        actuator.perform(event, strength: strength)
    }
}
