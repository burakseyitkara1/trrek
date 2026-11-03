import CMultitouch
import CoreFoundation
import Foundation
import IOKit

/// A multitouch device together with its physical surface size and haptic identifier.
public struct MultitouchDeviceInfo {
    public let ref: MTDeviceRef
    public let isBuiltIn: Bool
    public let widthMM: Float
    public let heightMM: Float
    public let multitouchID: UInt64?
}

public enum MultitouchDevices {
    /// Device lists returned by the framework own their device references. Only the latest list is kept
    /// alive; the previous one is released when a new enumeration replaces it.
    private nonisolated(unsafe) static var latestList: CFArray?
    private static let listLock = NSLock()

    /// Lists all multitouch devices. Returns an empty array when the framework is unavailable.
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
            devices.append(MultitouchDeviceInfo(
                ref: ref,
                isBuiltIn: builtIn,
                widthMM: Float(width) / 100,
                heightMM: Float(height) / 100,
                multitouchID: registry.take(builtIn: builtIn)
            ))
        }
        return devices
    }

    /// Haptic identifiers from the I/O Registry, split by the built-in flag. Built-in devices
    /// map to built-in entries; external devices take the remaining entries in order.
    private struct RegistryEntries {
        var builtIn: [UInt64] = []
        var external: [UInt64] = []

        mutating func take(builtIn isBuiltIn: Bool) -> UInt64? {
            if isBuiltIn {
                return builtIn.isEmpty ? nil : builtIn.removeFirst()
            }
            return external.isEmpty ? nil : external.removeFirst()
        }
    }

    private static func registryEntries() -> RegistryEntries {
        var entries = RegistryEntries()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator
        ) == KERN_SUCCESS else { return entries }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let identifier = property(service, "Multitouch ID") as? NSNumber else { continue }
            let builtIn = (property(service, "MT Built-In") as? NSNumber)?.boolValue ?? false
            if builtIn {
                entries.builtIn.append(identifier.uint64Value)
            } else {
                entries.external.append(identifier.uint64Value)
            }
        }
        return entries
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
