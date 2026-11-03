import CMultitouch
import TrrekEngine

/// Turns one raw contact frame into an engine `Frame` on the stack.
public enum FrameConverter {
    /// Contact states that mean a finger is on the surface: 3 = touch began, 4 = touching.
    private static let touchBegan: Int32 = 3
    private static let touching: Int32 = 4

    /// Keeps only touching contacts; anything past `TouchBuffer.capacity` is dropped. Never allocates.
    public static func frame(
        touches: UnsafeBufferPointer<MTTouch>,
        timestamp: Double,
        deviceID: UInt64,
        geometry: DeviceGeometry
    ) -> Frame {
        var buffer = TouchBuffer()
        for touch in touches where touch.state == touchBegan || touch.state == touching {
            let accepted = buffer.append(Touch(
                id: touch.identifier,
                x: touch.nx,
                y: touch.ny,
                majorAxisMM: touch.majorAxis
            ))
            if !accepted {
                break
            }
        }
        return Frame(deviceID: deviceID, timestamp: timestamp, geometry: geometry, touches: buffer)
    }
}
