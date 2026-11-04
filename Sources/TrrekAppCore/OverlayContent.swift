import TrrekPlatform

/// What the level overlay shows for a level in 0...1.
public enum OverlayContent {
    /// The number of segments in the level bar.
    public static let segmentCount = 16

    /// How many of the bar's segments are lit; levels outside 0...1, and non-finite ones, are clamped.
    public static func filledSegments(for level: Float) -> Int {
        let clamped = clamp(level)
        return Int((clamped * Float(segmentCount)).rounded())
    }

    /// `label` when given, otherwise the level as a whole percentage ("50%").
    public static func text(level: Float, label: String?) -> String {
        if let label {
            return label
        }
        return "\(Int((clamp(level) * 100).rounded()))%"
    }

    /// The net scrub distance as signed seconds ("+15 s", "\u{2212}10 s", "0 s"), assuming 5 s per step.
    public static func scrubLabel(steps: Int) -> String {
        ScrubLabel.text(steps: steps)
    }

    public static func symbol(for kind: OverlayKind) -> String {
        switch kind {
        case .keyboardBacklight: "keyboard"
        case .externalBrightness: "sun.max"
        case .scrub: "film"
        }
    }

    private static func clamp(_ level: Float) -> Float {
        level.isFinite ? min(max(level, 0), 1) : 0
    }
}
