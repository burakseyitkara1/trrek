import AppKit
import Testing
import TrrekAppCore
import TrrekPlatform

@Test func overlayTextShowsPercentageOrLabel() {
    #expect(OverlayContent.text(level: 0.5, label: nil) == "50%")
    #expect(OverlayContent.text(level: 0, label: nil) == "0%")
    #expect(OverlayContent.text(level: 1, label: nil) == "100%")
    #expect(OverlayContent.text(level: 0.125, label: nil) == "13%")
    #expect(OverlayContent.text(level: 0.5, label: "1:05") == "1:05")
    #expect(OverlayContent.text(level: .nan, label: nil) == "0%")
}

@Test func overlayBarFillsRoundedSegments() {
    #expect(OverlayContent.segmentCount == 16)
    #expect(OverlayContent.filledSegments(for: 0.5) == 8)
    #expect(OverlayContent.filledSegments(for: 0) == 0)
    #expect(OverlayContent.filledSegments(for: 1) == 16)
    #expect(OverlayContent.filledSegments(for: 0.03) == 0)
    #expect(OverlayContent.filledSegments(for: 0.04) == 1)
    #expect(OverlayContent.filledSegments(for: 1.7) == 16)
    #expect(OverlayContent.filledSegments(for: -0.2) == 0)
    #expect(OverlayContent.filledSegments(for: .infinity) == 0)
}

@Test func overlaySymbols() {
    #expect(OverlayContent.symbol(for: .keyboardBacklight) == "keyboard")
    #expect(OverlayContent.symbol(for: .externalBrightness) == "sun.max")
    #expect(OverlayContent.symbol(for: .scrub) == "film")
}

@Test func labelsAreShownThroughTheirLocalization() {
    // Tests have no translations, so the English text comes back unchanged.
    #expect(OverlayContent.text(level: 0.5, label: "+15 s") == "+15 s")
    #expect(OverlayContent.text(level: 0.5, label: "\u{2212}10 s") == "\u{2212}10 s")
    #expect(OverlayContent.text(level: 0.5, label: "No DDC") == "No DDC")
    #expect(OverlayContent.text(level: 0.5, label: nil) == "50%")
}

@Test func scrubLabelShowsSignedSeconds() {
    #expect(OverlayContent.scrubLabel(steps: 3) == "+15 s")
    #expect(OverlayContent.scrubLabel(steps: -2) == "\u{2212}10 s")
    #expect(OverlayContent.scrubLabel(steps: 0) == "0 s")
}

@Test func labelsReplaceTheBar() {
    #expect(OverlayContent.showsBar(kind: .keyboardBacklight, label: nil))
    #expect(OverlayContent.showsBar(kind: .externalBrightness, label: nil))
    #expect(!OverlayContent.showsBar(kind: .externalBrightness, label: "No DDC"))
    #expect(!OverlayContent.showsBar(kind: .scrub, label: "+15 s"))
    #expect(!OverlayContent.showsBar(kind: .scrub, label: nil))
}

/// Measured with the overlay's font: the level row fits the panel, "100%" fits its fixed column, and the widest
/// labels fit beside the symbol.
@Test func overlayTextFitsThePanel() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: OverlayLayout.fontSize, weight: .semibold)
    func width(_ text: String) -> Double {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    #expect(OverlayLayout.levelRowWidth <= OverlayLayout.width)
    #expect(width(OverlayContent.text(level: 1, label: nil)) <= OverlayLayout.levelTextWidth)
    // English and the longest Turkish forms ("%100", "DDC yok", "+1000 sn").
    #expect(width("%100") <= OverlayLayout.levelTextWidth)
    let labels = [
        "No DDC",
        "DDC yok",
        "+1000 sn",
        "\u{2212}1000 sn",
        OverlayContent.scrubLabel(steps: 20),
        OverlayContent.scrubLabel(steps: -20),
        OverlayContent.scrubLabel(steps: 200),
        OverlayContent.scrubLabel(steps: -200)
    ]
    for label in labels {
        #expect(width(label) <= OverlayLayout.maximumLabelWidth, "\(label)")
    }
    #expect(OverlayLayout.height == 56)
}
