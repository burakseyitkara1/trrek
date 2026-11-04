import CMultitouch
import CoreFoundation
import Darwin
import IOKit
import os

let platformLogger = Logger(subsystem: "com.burakseyitkara.trrek", category: "platform")

/// Function pointers resolved from the system multitouch framework.
public struct MultitouchSymbols: Sendable {
    public let createList: @convention(c) () -> Unmanaged<CFArray>?
    public let isBuiltIn: @convention(c) (MTDeviceRef) -> Bool
    public let surfaceDimensions: @convention(c) (
        MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Int32
    public let registerFrameCallback: @convention(c) (MTDeviceRef, MTFrameCallback) -> Void
    public let unregisterFrameCallback: @convention(c) (MTDeviceRef, MTFrameCallback) -> Void
    public let start: @convention(c) (MTDeviceRef, Int32) -> Int32
    public let stop: @convention(c) (MTDeviceRef) -> Int32
    public let release: @convention(c) (MTDeviceRef) -> Void
    /// The device's multitouch ID (the registry's "Multitouch ID"); optional, since only device matching uses it.
    public let deviceID: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32)?
}

/// Names in the I/O Registry entries of the system multitouch driver.
enum MultitouchRegistryKeys {
    static let deviceClass = "AppleMultitouchDevice"
    static let multitouchID = "Multitouch ID"
    static let builtIn = "MT Built-In"
}

/// Function pointers for the trackpad haptic actuator.
public struct ActuatorSymbols: Sendable {
    public let createFromDeviceID: @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    public let open: @convention(c) (CFTypeRef) -> Int32
    public let actuate: @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32
    public let close: @convention(c) (CFTypeRef) -> Int32
}

/// Names of the keyboard backlight client in the system brightness framework. The framework is loaded when
/// this group is first read; the bridge looks the class and selectors up through the Objective-C runtime.
public struct CoreBrightnessSymbols: Sendable {
    public let clientClassName: String
    /// `- (NSArray *)copy…`: the backlight IDs of the attached keyboards (returned retained).
    public let copyKeyboardIDsSelector: String
    /// `- (float)…:(unsigned long long)keyboardID`: the current level in 0...1.
    public let brightnessSelector: String
    /// `- (BOOL)…:(float)level …:(int)fadeSpeed …:(BOOL)commit …:(unsigned long long)keyboardID`.
    public let setBrightnessSelector: String
}

/// Function pointers for the display audio/video service, which carries I2C transfers to an external display.
public struct AVServiceSymbols: Sendable {
    /// Creates the service object for an I/O Registry entry (returned retained).
    public let createWithService: @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    /// `(service, chipAddress, offset, buffer, length)`: reads `length` bytes from the I2C device.
    public let readI2C: @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    /// `(service, chipAddress, dataAddress, buffer, length)`: writes `dataAddress` followed by `length` bytes.
    public let writeI2C: @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
}

/// Names in the I/O Registry entries of external displays.
enum DisplayRegistryKeys {
    static let avServiceClass = "DCPAVServiceProxy"
    static let location = "Location"
    static let external = "External"
    static let displayAttributes = "DisplayAttributes"
    static let productAttributes = "ProductAttributes"
    static let manufacturerID = "ManufacturerID"
    static let productID = "ProductID"
    static let serialNumber = "SerialNumber"
}

/// The only place where private framework symbols are resolved. A group whose symbols
/// cannot all be found is `nil`; callers then disable the feature instead of crashing.
public enum PrivateSymbols {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private struct Handle: @unchecked Sendable {
        let raw: UnsafeMutableRawPointer?
    }

    private static let handle: Handle = {
        let raw = dlopen(frameworkPath, RTLD_NOW)
        if raw == nil {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            platformLogger.error("dlopen failed: \(reason, privacy: .public)")
        }
        return Handle(raw: raw)
    }()

    public static let multitouch: MultitouchSymbols? = {
        guard
            let createList = resolve("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
            let isBuiltIn = resolve("MTDeviceIsBuiltIn", as: (@convention(c) (MTDeviceRef) -> Bool).self),
            let surfaceDimensions = resolve(
                "MTDeviceGetSensorSurfaceDimensions",
                as: (@convention(c) (
                    MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
                ) -> Int32).self
            ),
            let register = resolve(
                "MTRegisterContactFrameCallback",
                as: (@convention(c) (MTDeviceRef, MTFrameCallback) -> Void).self
            ),
            let unregister = resolve(
                "MTUnregisterContactFrameCallback",
                as: (@convention(c) (MTDeviceRef, MTFrameCallback) -> Void).self
            ),
            let start = resolve("MTDeviceStart", as: (@convention(c) (MTDeviceRef, Int32) -> Int32).self),
            let stop = resolve("MTDeviceStop", as: (@convention(c) (MTDeviceRef) -> Int32).self),
            let release = resolve("MTDeviceRelease", as: (@convention(c) (MTDeviceRef) -> Void).self)
        else {
            platformLogger.error("multitouch symbols unavailable; touch input disabled")
            return nil
        }
        return MultitouchSymbols(
            createList: createList,
            isBuiltIn: isBuiltIn,
            surfaceDimensions: surfaceDimensions,
            registerFrameCallback: register,
            unregisterFrameCallback: unregister,
            start: start,
            stop: stop,
            release: release,
            deviceID: resolve(
                "MTDeviceGetDeviceID",
                as: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<UInt64>) -> Int32).self
            )
        )
    }()

    public static let actuator: ActuatorSymbols? = {
        guard
            let create = resolve(
                "MTActuatorCreateFromDeviceID",
                as: (@convention(c) (UInt64) -> Unmanaged<CFTypeRef>?).self
            ),
            let open = resolve("MTActuatorOpen", as: (@convention(c) (CFTypeRef) -> Int32).self),
            let actuate = resolve(
                "MTActuatorActuate",
                as: (@convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32).self
            ),
            let close = resolve("MTActuatorClose", as: (@convention(c) (CFTypeRef) -> Int32).self)
        else {
            platformLogger.error("actuator symbols unavailable; haptics disabled")
            return nil
        }
        return ActuatorSymbols(createFromDeviceID: create, open: open, actuate: actuate, close: close)
    }()

    private static let coreBrightnessPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    public static let coreBrightness: CoreBrightnessSymbols? = {
        guard dlopen(coreBrightnessPath, RTLD_NOW) != nil else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            platformLogger.error("brightness framework unavailable: \(reason, privacy: .public)")
            return nil
        }
        return CoreBrightnessSymbols(
            clientClassName: "KeyboardBrightnessClient",
            copyKeyboardIDsSelector: "copyKeyboardBacklightIDs",
            brightnessSelector: "brightnessForKeyboard:",
            setBrightnessSelector: "setBrightness:fadeSpeed:commit:forKeyboard:"
        )
    }()

    private static let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    private static let ioKitHandle: Handle = {
        let raw = dlopen(ioKitPath, RTLD_NOW)
        if raw == nil {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            platformLogger.error("dlopen failed: \(reason, privacy: .public)")
        }
        return Handle(raw: raw)
    }()

    public static let avService: AVServiceSymbols? = {
        typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
        guard
            let create = resolve(
                "IOAVServiceCreateWithService",
                as: (@convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?).self,
                in: ioKitHandle
            ),
            let read = resolve("IOAVServiceReadI2C", as: Transfer.self, in: ioKitHandle),
            let write = resolve("IOAVServiceWriteI2C", as: Transfer.self, in: ioKitHandle)
        else {
            platformLogger.error("display service symbols unavailable; external brightness disabled")
            return nil
        }
        return AVServiceSymbols(createWithService: create, readI2C: read, writeI2C: write)
    }()

    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        resolve(name, as: type, in: handle)
    }

    private static func resolve<T>(_ name: String, as type: T.Type, in handle: Handle) -> T? {
        guard let raw = handle.raw else { return nil }
        guard let symbol = dlsym(raw, name) else {
            platformLogger.error("missing symbol \(name, privacy: .public)")
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}
