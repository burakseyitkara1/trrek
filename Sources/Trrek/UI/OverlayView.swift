import SwiftUI
import TrrekAppCore
import TrrekPlatform

/// The level overlay's content: a glass capsule with the kind's symbol, a segmented level bar and the level as
/// text, or the symbol and a label (the scrub distance, "No DDC") without the bar.
struct OverlayView: View {
    let kind: OverlayKind
    let level: Float
    let label: String?

    var body: some View {
        let filled = OverlayContent.filledSegments(for: level)
        let text = OverlayContent.text(level: level, label: label)
        HStack(spacing: OverlayLayout.spacing) {
            Image(systemName: OverlayContent.symbol(for: kind))
                .font(.system(size: 17, weight: .semibold))
                .frame(width: OverlayLayout.symbolWidth)
            if OverlayContent.showsBar(kind: kind, label: label) {
                HStack(spacing: OverlayLayout.segmentSpacing) {
                    ForEach(0 ..< OverlayContent.segmentCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < filled ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: OverlayLayout.segmentWidth, height: 10)
                    }
                }
                Text(text)
                    .font(Self.font)
                    .lineLimit(1)
                    .frame(width: OverlayLayout.levelTextWidth, alignment: .trailing)
            } else {
                Spacer(minLength: 0)
                // A label takes its natural width; `OverlayLayout.maximumLabelWidth` leaves room for the widest.
                Text(text)
                    .font(Self.font)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, OverlayLayout.horizontalPadding)
        .frame(width: OverlayPanel.size.width, height: OverlayPanel.size.height)
        // The glass sits behind the content rather than around it, so the bar keeps its full contrast instead of
        // taking on the glass's vibrancy.
        .background {
            Color.clear.glassEffect(.regular, in: .capsule)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityName(of: kind))
        .accessibilityValue(text)
    }

    private static let font = Font.system(size: OverlayLayout.fontSize, weight: .semibold).monospacedDigit()

    private static func accessibilityName(of kind: OverlayKind) -> String {
        switch kind {
        case .keyboardBacklight: String(localized: "Keyboard backlight", bundle: .main)
        case .externalBrightness: String(localized: "Display brightness", bundle: .main)
        case .scrub: String(localized: "Video position", bundle: .main)
        }
    }
}
