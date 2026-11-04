import Foundation
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

    /// Whether the segmented bar is drawn. A label replaces it: the scrub distance has no level, and neither does
    /// a "No DDC" result.
    public static func showsBar(kind: OverlayKind, label: String?) -> Bool {
        kind != .scrub && label == nil
    }

    /// `label` when given, otherwise the level as a whole percentage ("50%"). Both are localized: the percentage
    /// with its format ("%lld%%"); a scrub distance ("+15 s") with its unit's format ("%@ s"); any other label by
    /// looking it up as a key ("No DDC"). The labels arrive as fixed English text from the frame thread and are
    /// translated here, on the main thread.
    public static func text(level: Float, label: String?) -> String {
        if let label {
            if label.hasSuffix(scrubUnitSuffix) {
                let value = String(label.dropLast(scrubUnitSuffix.count))
                return String(localized: "\(value) s", bundle: .main)
            }
            return Bundle.main.localizedString(forKey: label, value: label, table: nil)
        }
        let percent = Int((clamp(level) * 100).rounded())
        return String(localized: "\(percent)%", bundle: .main)
    }

    /// The net scrub distance as signed seconds ("+15 s", "\u{2212}10 s", "0 s"), assuming 5 s per step.
    /// The unit `ScrubLabel` ends its text with.
    private static let scrubUnitSuffix = " s"

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

/// The overlay's geometry in points. A level row is symbol, bar and a fixed-width percentage; a label row is the
/// symbol and the label at its natural width, so text such as "No DDC" or "+100 s" is never cut.
public enum OverlayLayout {
    public static let width: Double = 240
    public static let height: Double = 56
    public static let horizontalPadding: Double = 16
    public static let spacing: Double = 12
    public static let symbolWidth: Double = 24
    public static let segmentWidth: Double = 5
    public static let segmentSpacing: Double = 2
    /// Wide enough for "100%".
    public static let levelTextWidth: Double = 40
    public static let fontSize: Double = 13

    public static var barWidth: Double {
        Double(OverlayContent.segmentCount) * segmentWidth + Double(OverlayContent.segmentCount - 1) * segmentSpacing
    }

    /// The width of a level row's content and padding.
    public static var levelRowWidth: Double {
        2 * horizontalPadding + symbolWidth + spacing + barWidth + spacing + levelTextWidth
    }

    /// The widest label that fits: a label row is the symbol, a spacer and the label, so the spacing appears twice.
    public static var maximumLabelWidth: Double {
        width - 2 * horizontalPadding - symbolWidth - 2 * spacing
    }
}
