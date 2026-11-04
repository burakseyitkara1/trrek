import CoreGraphics

/// Finds the display the user is looking at: the one under the pointer.
public enum DisplayLocator {
    /// The display that contains the pointer, or `nil` when it cannot be determined.
    public static func displayUnderPointer() -> CGDirectDisplayID? {
        // An event created without a source carries the current pointer location in global display coordinates,
        // the space the display lookup uses.
        guard let point = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }
}
