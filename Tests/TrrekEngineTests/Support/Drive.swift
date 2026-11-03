import Foundation
@testable import TrrekEngine

extension GestureEngine {
    /// Moves finger `id` in a straight line from `from` to `to` (mm), one frame every `stepMM` of travel
    /// and every `dt` seconds starting at `startT`, with contact size `major` (mm). Both end points get a frame.
    /// Returns the last timestamp.
    @discardableResult
    func drive(
        _ fb: FrameBuilder,
        id: Int32,
        from: (Float, Float),
        to: (Float, Float),
        stepMM: Float = 1,
        dt: TimeInterval = 0.008,
        major: Float = 8,
        startT: TimeInterval
    ) -> TimeInterval {
        let dx = to.0 - from.0
        let dy = to.1 - from.1
        let distance = (dx * dx + dy * dy).squareRoot()
        let segments = distance > 0 ? Int((distance / stepMM).rounded(.up)) : 0
        var t = startT
        for index in 0 ... segments {
            let travelled = min(Float(index) * stepMM, distance)
            let xMM = distance > 0 ? from.0 + (dx * travelled) / distance : from.0
            let yMM = distance > 0 ? from.1 + (dy * travelled) / distance : from.1
            t = startT + Double(index) * dt
            process(fb.frame(t: t, [(id, xMM, yMM)], major: major))
        }
        return t
    }
}
