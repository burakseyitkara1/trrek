import CoreFoundation

/// Drives the trackpad haptic actuator. The actuator stays open for the object's lifetime.
public final class ActuatorHaptics {
    private let symbols: ActuatorSymbols
    private let actuator: CFTypeRef

    public init?(multitouchID: UInt64) {
        guard let symbols = PrivateSymbols.actuator else { return nil }
        guard let actuator = symbols.createFromDeviceID(multitouchID)?.takeRetainedValue() else {
            platformLogger.error("actuator create failed for device \(multitouchID, privacy: .public)")
            return nil
        }
        let result = symbols.open(actuator)
        guard result == 0 else {
            platformLogger.error("actuator open failed: \(result, privacy: .public)")
            return nil
        }
        self.symbols = symbols
        self.actuator = actuator
    }

    deinit {
        _ = symbols.close(actuator)
    }

    /// Plays a waveform. Returns `true` when the actuator accepted it.
    @discardableResult
    public func actuate(waveform: Int32) -> Bool {
        symbols.actuate(actuator, waveform, 0, 0.0, 0.0) == 0
    }
}
