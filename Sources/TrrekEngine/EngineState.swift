import Foundation

/// A finger resting in an edge strip or corner that has not yet moved far enough to start a slide.
/// Coordinates are normalized (0...1, origin bottom-left), like `Touch`.
struct CandidateData {
    var zone: Zone
    var touchID: Int32
    var x0: Float
    var y0: Float
    var t0: TimeInterval
    /// Largest per-axis distance from (x0, y0) seen so far, in mm; decides whether a lift is a tap.
    var maxMoveMM: Float = 0

    /// The finger where it landed.
    var origin: Touch {
        Touch(id: touchID, x: x0, y: y0, majorAxisMM: 0)
    }
}

/// An active slide along one edge.
struct SlideData {
    var edge: Edge
    var action: EdgeAction
    /// When and where the sliding finger first touched down (the candidate's `t0`, `x0`, `y0`).
    var firstDownTime: TimeInterval
    var origin: Touch
    var touchID: Int32
    /// Position of the tracked finger in the previous frame; each frame adds the movement since then.
    var previous: Touch
    /// Distance along the edge not yet turned into steps, in mm (signed).
    var accumulatedMM: Float
    var stepsEmitted: Int
    var lastFrameTime: TimeInterval
    /// Whether `freezeCursor(true)` was emitted at the start and must be undone at the end.
    var frozen: Bool
}

/// The previous single tap on a corner or media edge; exactly one of `corner` and `edge` is set.
typealias TapRecord = (corner: Corner?, edge: Edge?, at: TimeInterval) // swiftlint:disable:this large_tuple

/// The ids of the three fingers of a possible middle click.
typealias ThreeFingerIDs = (Int32, Int32, Int32) // swiftlint:disable:this large_tuple

/// The engine's single state, shared by all devices. Pure value type: changing state never allocates.
enum EngineState {
    case idle
    case candidate(CandidateData)
    case sliding(SlideData)
    case lost(SlideData, since: TimeInterval)
    /// Fingers that will not produce a gesture until all of them lift. `start` holds each finger's position
    /// when it joined (used by the three-finger movement check).
    case spent(firstDownTime: TimeInterval, start: TouchBuffer)
    /// Three fingers down together, a possible middle click. `start` holds their positions when they landed;
    /// `tDown` is when the first of them touched down.
    case threeFinger(ids: ThreeFingerIDs, start: TouchBuffer, tDown: TimeInterval)
}
