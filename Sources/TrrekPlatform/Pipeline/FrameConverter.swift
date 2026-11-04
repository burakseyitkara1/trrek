import CMultitouch
import TrrekEngine

/// Turns one raw contact frame into an engine `Frame` on the stack.
public enum FrameConverter {
    /// Contact states that mean a finger is on the surface: 3 = touch began, 4 = touching.
    private static let touchBegan: Int32 = 3
    private static let touching: Int32 = 4

    /// Ranges a plausible contact stays within: normalized positions with a small margin, and a major axis in
    /// millimetres.
    private static let positionRange: ClosedRange<Float> = -0.05 ... 1.05
    private static let majorAxisRange: ClosedRange<Float> = 0 ... 100

    /// Whether every contact lies within the plausible ranges; non-finite values fail. Never allocates.
    public static func isPlausible(_ touches: UnsafeBufferPointer<MTTouch>) -> Bool {
        for touch in touches {
            guard positionRange.contains(touch.nx), positionRange.contains(touch.ny),
                  majorAxisRange.contains(touch.majorAxis)
            else { return false }
        }
        return true
    }

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
