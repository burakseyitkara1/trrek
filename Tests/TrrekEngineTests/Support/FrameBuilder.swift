import Foundation
@testable import TrrekEngine

/// Builds synthetic frames from millimetre positions (origin bottom-left, y up).
struct FrameBuilder {
    var geometry = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)
    var deviceID: UInt64 = 1

    // swiftlint:disable:next large_tuple
    func frame(t: TimeInterval, _ touches: [(id: Int32, xMM: Float, yMM: Float)], major: Float = 8) -> Frame {
        var buffer = TouchBuffer()
        for touch in touches {
            buffer.append(Touch(
                id: touch.id,
                x: touch.xMM / geometry.widthMM,
                y: touch.yMM / geometry.heightMM,
                majorAxisMM: major
            ))
        }
        return Frame(deviceID: deviceID, timestamp: t, geometry: geometry, touches: buffer)
    }
}
