import AudioToolbox
import CoreAudio
import CoreGraphics

/// The output volume of the default output device, through the public audio hardware properties. Unknown while the
/// device is muted (a volume key unmutes it, so the level says nothing about the next step) or when the device has
/// no volume control.
public struct OutputVolumeReader: LevelReading {
    public init() {}

    public func level() -> Float? {
        guard let device = Self.defaultOutputDevice(), !Self.isMuted(device) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr, volume.isFinite
        else { return nil }
        return min(max(volume, 0), 1)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        else { return false }
        return muted != 0
    }
}

/// The brightness of the built-in display. `nil` (no reader) when the display brightness symbols are missing; the
/// level is unknown while no built-in display is online (lid closed).
public struct BuiltInBrightnessReader: LevelReading {
    private static let maxDisplays = 16
    private let symbols: DisplayServicesSymbols

    public init?() {
        guard let symbols = PrivateSymbols.displayServices else { return nil }
        self.symbols = symbols
    }

    public func level() -> Float? {
        guard let display = Self.builtInDisplay() else { return nil }
        var value: Float = 0
        guard symbols.getBrightness(display, &value) == 0, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    /// The first online built-in display; the list lives on the stack.
    private static func builtInDisplay() -> CGDirectDisplayID? {
        withUnsafeTemporaryAllocation(of: CGDirectDisplayID.self, capacity: maxDisplays) { buffer in
            var count: UInt32 = 0
            guard let base = buffer.baseAddress,
                  CGGetOnlineDisplayList(UInt32(maxDisplays), base, &count) == .success
            else { return nil }
            return buffer.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
        }
    }
}

/// Where a level stops a step: at or above 0.999 going up, at or below 0.001 going down.
public enum LevelBounds {
    public static func isAtBound(_ level: Float, direction: Int) -> Bool {
        direction > 0 ? level >= 0.999 : direction < 0 && level <= 0.001
    }
}
