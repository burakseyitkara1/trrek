import CMultitouch
import Foundation

public enum RawFrameStreamError: Error {
    case symbolsUnavailable
    case noDevices
    case startFailed
}

/// Non-capturing C callback; forwards every frame to the active stream.
private let frameCallback: MTFrameCallback = { device, touches, count, timestamp, _ in
    RawFrameStream.current?.dispatch(device, touches, count, timestamp)
}

/// Delivers raw contact frames from one or more multitouch devices.
/// `onFrame` runs on the framework's callback thread and must be set before `start()`.
public final class RawFrameStream {
    nonisolated(unsafe) weak static var current: RawFrameStream?

    /// Receives the device, its contacts (valid only during the call) and the frame timestamp in seconds.
    public var onFrame: (@Sendable (MTDeviceRef, UnsafeBufferPointer<MTTouch>, Double) -> Void)?

    private let devices: [MultitouchDeviceInfo]
    private var startedDevices: [MTDeviceRef] = []

    public init(devices: [MultitouchDeviceInfo]) {
        self.devices = devices
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard let symbols = PrivateSymbols.multitouch else { throw RawFrameStreamError.symbolsUnavailable }
        guard !devices.isEmpty else { throw RawFrameStreamError.noDevices }
        stop()
        RawFrameStream.current = self
        for device in devices {
            symbols.registerFrameCallback(device.ref, frameCallback)
            let result = symbols.start(device.ref, 0)
            platformLogger.info(
                "device start (built-in: \(device.isBuiltIn, privacy: .public)) returned \(result, privacy: .public)"
            )
            if result == 0 {
                startedDevices.append(device.ref)
            } else {
                symbols.unregisterFrameCallback(device.ref, frameCallback)
            }
        }
        if startedDevices.isEmpty {
            RawFrameStream.current = nil
            throw RawFrameStreamError.startFailed
        }
    }

    /// Stops every started device. A frame that is already in flight on the framework's thread may still
    /// invoke `onFrame` once after this returns, so the handler must stay valid until then.
    public func stop() {
        guard let symbols = PrivateSymbols.multitouch else { return }
        for device in startedDevices {
            symbols.unregisterFrameCallback(device, frameCallback)
            _ = symbols.stop(device)
        }
        startedDevices.removeAll()
        if RawFrameStream.current === self {
            RawFrameStream.current = nil
        }
    }

    fileprivate func dispatch(
        _ device: MTDeviceRef?,
        _ touches: UnsafeMutablePointer<MTTouch>?,
        _ count: Int32,
        _ timestamp: Double
    ) {
        guard let device, let onFrame else { return }
        let length = touches == nil ? 0 : Int(max(count, 0))
        onFrame(device, UnsafeBufferPointer(start: touches, count: length), timestamp)
    }
}
