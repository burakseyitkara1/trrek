import SwiftUI
import TrrekAppCore
import TrrekPlatform

/// The level overlay's content: a glass capsule with the kind's symbol, a segmented level bar and the level as
/// text.
struct OverlayView: View {
    let kind: OverlayKind
    let level: Float
    let label: String?

    var body: some View {
        let filled = OverlayContent.filledSegments(for: level)
        let text = OverlayContent.text(level: level, label: label)
        HStack(spacing: 12) {
            Image(systemName: OverlayContent.symbol(for: kind))
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 24)
            if kind == .scrub {
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 2) {
                    ForEach(0 ..< OverlayContent.segmentCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < filled ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: 5, height: 10)
                    }
                }
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
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

    private static func accessibilityName(of kind: OverlayKind) -> String {
        switch kind {
        case .keyboardBacklight: "Keyboard backlight"
        case .externalBrightness: "Display brightness"
        case .scrub: "Video position"
        }
    }
}
