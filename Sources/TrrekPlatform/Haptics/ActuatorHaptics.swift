import CoreFoundation
import Dispatch
import os
import TrrekEngine

/// Drives the trackpad haptic actuator. The actuator stays open for the object's lifetime.
/// Actuation is serialized by a lock, so the object may be used from any thread.
public final class ActuatorHaptics: @unchecked Sendable {
    /// Delay before the second pulse of a strong start or tap.
    private static let secondPulseDelay: DispatchTimeInterval = .milliseconds(60)

    private let symbols: ActuatorSymbols
    private let actuator: CFTypeRef
    private let lock = OSAllocatedUnfairLock()

    public init?(multitouchID: UInt64) {
        guard let symbols = PrivateSymbols.actuator else { return nil }
        guard let actuator = symbols.createFromDeviceID(multitouchID)?.takeRetainedValue() else {
            platformLogger.error("actuator create failed for device \(multitouchID, privacy: .private(mask: .hash))")
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
        lock.withLock {
            symbols.actuate(actuator, waveform, 0, 0.0, 0.0) == 0
        }
    }
}

extension ActuatorHaptics: HapticActuating {
    /// Plays the waveform for `strength`; a strong start or tap adds a second pulse 60 ms later.
    public func perform(_ event: HapticEvent, strength: HapticStrength) {
        let waveform: Int32
        switch strength {
        case .off: return
        case .light: waveform = 4
        case .medium: waveform = 5
        case .strong: waveform = 6
        }
        actuate(waveform: waveform)
        guard strength == .strong, event == .start || event == .tap else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.secondPulseDelay) { [self] in
            actuate(waveform: waveform)
        }
    }
}
