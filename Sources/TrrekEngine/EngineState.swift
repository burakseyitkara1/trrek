import Foundation

/// A finger resting in an edge strip or corner that has not yet moved far enough to start a slide.
/// Coordinates are normalized (0...1, origin bottom-left), like `Touch`.
struct CandidateData {
    var zone: Zone
    var touchID: Int32
    var x0: Float
    var y0: Float
    var t0: TimeInterval
}

/// An active slide along one edge.
struct SlideData {
    var edge: Edge
    var action: EdgeAction
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

/// Three fingers down together; transitions are filled in by the multi-finger rules.
struct ThreeFingerData {
    var ids: InlineArray<3, Int32>
    var tDown: TimeInterval
    var maxMoveMM: Float
}

/// The engine's single state, shared by all devices. Pure value type: changing state never allocates.
enum EngineState {
    case idle
    case candidate(CandidateData)
    case sliding(SlideData)
    case lost(SlideData, since: TimeInterval)
    case spent(firstDownTime: TimeInterval)
    case threeFinger(ThreeFingerData)
}
