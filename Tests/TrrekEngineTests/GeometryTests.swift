import Testing
@testable import TrrekEngine

private let pad = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)

private func touch(_ xMM: Float, _ yMM: Float) -> Touch {
    Touch(id: 1, x: xMM / 120, y: yMM / 80, majorAxisMM: 8)
}

@Test func rightStripDetectedWithStandardWidth() {
    let cfg = EngineConfig()
    #expect(Geometry.zone(of: touch(115, 40), in: pad, config: cfg) == .edge(.right))
    #expect(Geometry.zone(of: touch(100, 40), in: pad, config: cfg) == .none)
}

@Test func cornerIsIntersectionOfStrips() {
    let cfg = EngineConfig()
    #expect(Geometry.zone(of: touch(115, 5), in: pad, config: cfg) == .corner(.bottomRight))
    #expect(Geometry.zone(of: touch(5, 5), in: pad, config: cfg) == .corner(.bottomLeft))
    #expect(Geometry.zone(of: touch(5, 75), in: pad, config: cfg) == .corner(.topLeft))
    #expect(Geometry.zone(of: touch(115, 75), in: pad, config: cfg) == .corner(.topRight))
}

@Test func offEdgeIsNotAZone() {
    var cfg = EngineConfig()
    #expect(Geometry.zone(of: touch(60, 78), in: pad, config: cfg) == .edge(.top))
    cfg.top = .off
    #expect(Geometry.zone(of: touch(60, 78), in: pad, config: cfg) == .none)
}

@Test func bottomQuarterOnlyLimitsVerticalEdges() {
    var cfg = EngineConfig()
    cfg.bottomQuarterOnly = true
    #expect(Geometry.zone(of: touch(115, 40), in: pad, config: cfg) == .none)
    #expect(Geometry.zone(of: touch(115, 15), in: pad, config: cfg) == .edge(.right))
    // Corners are kept: the option only restricts vertical-edge slides.
    #expect(Geometry.zone(of: touch(115, 75), in: pad, config: cfg) == .corner(.topRight))
    #expect(Geometry.zone(of: touch(115, 5), in: pad, config: cfg) == .corner(.bottomRight))
    // Horizontal edges are unaffected.
    #expect(Geometry.zone(of: touch(60, 78), in: pad, config: cfg) == .edge(.top))
}

@Test func edgeWidthNarrowAndWide() {
    var cfg = EngineConfig()
    cfg.thresholds.edgeWidthMM = 7
    #expect(Geometry.zone(of: touch(112, 40), in: pad, config: cfg) == .none)
    cfg.thresholds.edgeWidthMM = 14
    #expect(Geometry.zone(of: touch(112, 40), in: pad, config: cfg) == .edge(.right))
}

@Test func zeroGeometryYieldsNoZone() {
    let zero = DeviceGeometry(widthMM: 0, heightMM: 80, isBuiltIn: true)
    #expect(zero.isValid == false)
    #expect(Geometry.zone(of: touch(115, 40), in: zero, config: EngineConfig()) == .none)
}

@Test func deltaAlongVerticalEdgeIsPositiveUpward() {
    let delta = Geometry.deltaMM(edge: .right, from: touch(115, 15), to: touch(115, 35), in: pad)
    #expect(abs(delta.along - 20) < 0.001)
    #expect(abs(delta.perpendicular) < 0.001)
    let down = Geometry.deltaMM(edge: .left, from: touch(5, 35), to: touch(8, 15), in: pad)
    #expect(abs(down.along + 20) < 0.001)
    #expect(abs(down.perpendicular - 3) < 0.001)
}

@Test func deltaAlongHorizontalEdgeIsPositiveRightward() {
    let delta = Geometry.deltaMM(edge: .top, from: touch(30, 75), to: touch(50, 72), in: pad)
    #expect(abs(delta.along - 20) < 0.001)
    #expect(abs(delta.perpendicular + 3) < 0.001)
}

@Test func stepDistancesFollowThresholds() {
    let th = Thresholds()
    #expect(Geometry.stepMM(for: .volume, thresholds: th) == 3.75)
    #expect(Geometry.stepMM(for: .brightness, thresholds: th) == 3.75)
    #expect(Geometry.stepMM(for: .keyboardBacklight, thresholds: th) == 3.75)
    #expect(Geometry.stepMM(for: .switchApps, thresholds: th) == 12)
    #expect(Geometry.stepMM(for: .scrubVideo, thresholds: th) == 6)
    #expect(Geometry.stepMM(for: .media, thresholds: th) == 20)
    #expect(Geometry.stepMM(for: .off, thresholds: th) == .infinity)
}

@Test func cornerEdgesAndConfigDefaults() {
    #expect(Geometry.edges(of: .topLeft) == (.left, .top))
    #expect(Geometry.edges(of: .bottomRight) == (.right, .bottom))
    let cfg = EngineConfig()
    #expect(cfg.action(for: Edge.left) == .brightness)
    #expect(cfg.action(for: Edge.right) == .volume)
    #expect(cfg.action(for: Edge.top) == .switchApps)
    #expect(cfg.action(for: Edge.bottom) == .keyboardBacklight)
    #expect(Corner.allCases.allSatisfy { cfg.action(for: $0) == .off })
    #expect(cfg.freezeCursor && !cfg.precision && !cfg.bottomQuarterOnly)
}

@Test func cornerIgnoresWhetherItsEdgesAreOff() {
    var cfg = EngineConfig()
    cfg.left = .off
    #expect(Geometry.zone(of: touch(5, 78), in: pad, config: cfg) == .corner(.topLeft))
    cfg.top = .off
    #expect(Geometry.zone(of: touch(5, 78), in: pad, config: cfg) == .corner(.topLeft))
    // The plain edges stay off.
    #expect(Geometry.zone(of: touch(5, 40), in: pad, config: cfg) == .none)
    #expect(Geometry.zone(of: touch(60, 78), in: pad, config: cfg) == .none)
}
