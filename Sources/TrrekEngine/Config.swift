import Foundation

public enum EdgeAction: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case volume, brightness, switchApps, scrubVideo, keyboardBacklight, media, off
}

public enum CornerAction: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case off, mute, screenshot
}

public struct Thresholds: Sendable, Equatable, Hashable {
    public var edgeWidthMM: Float = 10
    public var slideStartMM: Float = 3
    public var abortPerpendicularMM: Float = 4
    public var stepMM: Float = 3.75
    public var appSwitchStepMM: Float = 12
    public var scrubStepMM: Float = 6
    public var mediaSkipStepMM: Float = 20
    public var tapMaxDuration: TimeInterval = 0.25
    public var tapMaxMoveMM: Float = 2
    public var doubleTapWindow: TimeInterval = 0.35
    public var lostTimeout: TimeInterval = 0.18
    public var threeFingerSettle: TimeInterval = 0.10
    public var threeFingerMaxDuration: TimeInterval = 0.30
    public var palmMajorAxisMM: Float = 20
    public var typingGate: TimeInterval = 0.40

    public init() {}
}

public struct EngineConfig: Sendable, Equatable, Hashable {
    public var left: EdgeAction = .brightness
    public var right: EdgeAction = .volume
    public var top: EdgeAction = .switchApps
    public var bottom: EdgeAction = .keyboardBacklight
    public var topLeft: CornerAction = .off
    public var topRight: CornerAction = .off
    public var bottomLeft: CornerAction = .off
    public var bottomRight: CornerAction = .off
    public var bottomQuarterOnly = false
    public var precision = false
    public var freezeCursor = true
    public var middleClickEnabled = false
    public var holdKeyRequired = false
    public var thresholds = Thresholds()

    public init() {}

    public func action(for edge: Edge) -> EdgeAction {
        switch edge {
        case .left: left
        case .right: right
        case .top: top
        case .bottom: bottom
        }
    }

    public func action(for corner: Corner) -> CornerAction {
        switch corner {
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomLeft: bottomLeft
        case .bottomRight: bottomRight
        }
    }
}
