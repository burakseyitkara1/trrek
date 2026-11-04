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

@Test func scrubLabelShowsSignedSeconds() {
    #expect(OverlayContent.scrubLabel(steps: 3) == "+15 s")
    #expect(OverlayContent.scrubLabel(steps: -2) == "\u{2212}10 s")
    #expect(OverlayContent.scrubLabel(steps: 0) == "0 s")
}
