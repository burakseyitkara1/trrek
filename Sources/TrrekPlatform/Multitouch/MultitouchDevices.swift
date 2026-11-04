import CMultitouch
import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

/// Whether a multitouch device is a trackpad, as far as its registry properties tell.
public enum MultitouchDeviceKind: Sendable, Equatable {
    /// A trackpad, built in or external: it drives gestures.
    case trackpad
    /// Some other multitouch device, such as a mouse with a touch surface: it never drives gestures.
    case other
    /// The properties say nothing either way; the device is used (fail open).
    case unknown

    /// Classifies a device from its multitouch registry entry's properties. Pure: reads `properties` only.
    ///
    /// Two public HID properties are consulted, both set by the system on every multitouch pointing device:
    /// - `HIDPointerAccelerationType` (`kIOHIDPointerAccelerationTypeKey`): the HID system picks the pointer
    ///   acceleration curve by this value, and trackpads carry `HIDTrackpadAcceleration`
    ///   (`kIOHIDTrackpadAccelerationType`); mice carry a mouse curve.
    /// - `DeviceUsagePairs` (`kIOHIDDeviceUsagePairsKey`): a trackpad lists the Digitizer page's Touch Pad usage
    ///   (`kHIDPage_Digitizer` / `kHIDUsage_Dig_TouchPad`), the standard HID usage for a touch pad.
    ///
    /// Either positive signal makes a trackpad. A device that has at least one of the properties but neither
    /// signal is `.other`. A device with neither property is `.unknown` and is kept, so a change in the
    /// registry layout can never switch the built-in trackpad off.
    public static func classify(_ properties: [String: Any]) -> MultitouchDeviceKind {
        let acceleration = properties[kIOHIDPointerAccelerationTypeKey] as? String
        let usagePairs = properties[kIOHIDDeviceUsagePairsKey] as? [[String: Any]]
        if acceleration == kIOHIDTrackpadAccelerationType {
            return .trackpad
        }
        if let usagePairs, usagePairs.contains(where: isTouchPadUsage) {
            return .trackpad
        }
        if acceleration != nil || usagePairs != nil {
            return .other
        }
        return .unknown
    }

    private static func isTouchPadUsage(_ pair: [String: Any]) -> Bool {
        (pair[kIOHIDDeviceUsagePageKey] as? Int) == kHIDPage_Digitizer
            && (pair[kIOHIDDeviceUsageKey] as? Int) == kHIDUsage_Dig_TouchPad
    }
}

/// A multitouch device together with its physical surface size, haptic identifier and kind.
public struct MultitouchDeviceInfo {
    public let ref: MTDeviceRef
    public let isBuiltIn: Bool
    public let widthMM: Float
    public let heightMM: Float
    public let multitouchID: UInt64?
    public let kind: MultitouchDeviceKind

    public init(
        ref: MTDeviceRef,
        isBuiltIn: Bool,
        widthMM: Float,
        heightMM: Float,
        multitouchID: UInt64?,
        kind: MultitouchDeviceKind = .unknown
    ) {
        self.ref = ref
        self.isBuiltIn = isBuiltIn
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.multitouchID = multitouchID
        self.kind = kind
    }
}

public enum MultitouchDevices {
    /// Device lists returned by the framework own their device references. Only the latest list is kept
    /// alive; the previous one is released when a new enumeration replaces it.
    private nonisolated(unsafe) static var latestList: CFArray?
    private static let listLock = NSLock()

    /// Lists all multitouch devices, trackpads or not. Returns an empty array when the framework is unavailable.
    ///
    /// Each call releases the list behind the previous call's `ref`s, so callers must stop every stream built
    /// from earlier results before enumerating again and must not use those earlier results afterwards.
    public static func enumerate() -> [MultitouchDeviceInfo] {
        guard let symbols = PrivateSymbols.multitouch,
              let list = symbols.createList()?.takeRetainedValue()
        else { return [] }

        listLock.lock()
        latestList = list
        listLock.unlock()

        var registry = registryEntries()
        var devices: [MultitouchDeviceInfo] = []
        for index in 0 ..< CFArrayGetCount(list) {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: value)
            let builtIn = symbols.isBuiltIn(ref)
            var width: Int32 = 0
            var height: Int32 = 0
            _ = symbols.surfaceDimensions(ref, &width, &height)
            let identifier = deviceID(of: ref, symbols)
            let entry = registry.take(id: identifier, builtIn: builtIn)
            if entry == nil {
                platformLogger.error("multitouch device without a registry entry; treating it as a trackpad")
            }
            devices.append(MultitouchDeviceInfo(
                ref: ref,
                isBuiltIn: builtIn,
                widthMM: Float(width) / 100,
                heightMM: Float(height) / 100,
                multitouchID: identifier ?? entry?.multitouchID,
                kind: entry?.kind ?? .unknown
            ))
        }
        return devices
    }

    /// The device's multitouch ID as the framework reports it, or `nil` when that function is unavailable.
    private static func deviceID(of ref: MTDeviceRef, _ symbols: MultitouchSymbols) -> UInt64? {
        guard let getID = symbols.deviceID else { return nil }
        var identifier: UInt64 = 0
        guard getID(ref, &identifier) == 0, identifier != 0 else { return nil }
        return identifier
    }

    // MARK: - I/O Registry

    struct RegistryEntry {
        let multitouchID: UInt64
        let isBuiltIn: Bool
        let kind: MultitouchDeviceKind
    }

    /// The multitouch registry entries not yet matched to a device.
    struct RegistryEntries {
        var entries: [RegistryEntry] = []

        /// Removes and returns the entry with multitouch ID `id`. Without an ID, or when no entry has it, falls
        /// back to the first entry with the same built-in flag: built-in devices map to built-in entries,
        /// external devices take the remaining entries in order.
        mutating func take(id: UInt64?, builtIn: Bool) -> RegistryEntry? {
            let index = id.flatMap { id in entries.firstIndex { $0.multitouchID == id } }
                ?? entries.firstIndex { $0.isBuiltIn == builtIn }
            return index.map { entries.remove(at: $0) }
        }
    }

    private static func registryEntries() -> RegistryEntries {
        var result = RegistryEntries()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(MultitouchRegistryKeys.deviceClass), &iterator
        ) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let identifier = property(service, MultitouchRegistryKeys.multitouchID) as? NSNumber else {
                continue
            }
            let builtIn = (property(service, MultitouchRegistryKeys.builtIn) as? NSNumber)?.boolValue ?? false
            var properties: [String: Any] = [:]
            for key in [kIOHIDPointerAccelerationTypeKey, kIOHIDDeviceUsagePairsKey] {
                properties[key] = property(service, key)
            }
            let kind = MultitouchDeviceKind.classify(properties)
            if kind == .unknown {
                let id = identifier.uint64Value
                platformLogger.error("multitouch device \(id, privacy: .public) has no kind; treating it as a trackpad")
            }
            result.entries.append(RegistryEntry(multitouchID: identifier.uint64Value, isBuiltIn: builtIn, kind: kind))
        }
        return result
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
