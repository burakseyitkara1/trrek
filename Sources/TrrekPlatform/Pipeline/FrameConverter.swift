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
    /// The contact states the framework uses (0 = not tracking … 7 = gone); anything else means the contact layout
    /// trrek reads is not the one delivered.
    private static let stateRange: ClosedRange<Int32> = 0 ... 7

    /// Whether any contact is touching the surface (state 3 or 4). Never allocates.
    public static func hasTouchingContact(_ touches: UnsafeBufferPointer<MTTouch>) -> Bool {
        touches.contains { isTouching($0) }
    }

    /// Whether any contact has a state outside 0...7, which no real frame has. Never allocates.
    public static func hasInvalidState(_ touches: UnsafeBufferPointer<MTTouch>) -> Bool {
        touches.contains { !stateRange.contains($0.state) }
    }

    /// Whether every contact has a known state and every touching contact lies within the plausible ranges;
    /// non-finite values fail. The positions and sizes of contacts in other states (hovering, lifting, gone) carry
    /// stale or undefined values and are not checked. Never allocates.
    public static func isPlausible(_ touches: UnsafeBufferPointer<MTTouch>) -> Bool {
        if hasInvalidState(touches) {
            return false
        }
        for touch in touches where isTouching(touch) {
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
        for touch in touches where isTouching(touch) {
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

    private static func isTouching(_ touch: MTTouch) -> Bool {
        touch.state == touchBegan || touch.state == touching
    }
}
