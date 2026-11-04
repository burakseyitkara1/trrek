import CoreGraphics
import Testing
import TrrekPlatform

@Test func targetStepsBySixteenthsOrSixtyFourths() {
    // 100 / 16 = 6 per step, 100 / 64 = 1 per fine step.
    #expect(ExternalBrightness.targetValue(current: 50, maximum: 100, steps: 1, fine: false) == 56)
    #expect(ExternalBrightness.targetValue(current: 50, maximum: 100, steps: -2, fine: false) == 38)
    #expect(ExternalBrightness.targetValue(current: 50, maximum: 100, steps: 3, fine: true) == 53)
    // A merged step moves by the whole count.
    #expect(ExternalBrightness.targetValue(current: 0, maximum: 640, steps: 10, fine: false) == 400)
    #expect(ExternalBrightness.targetValue(current: 0, maximum: 640, steps: 10, fine: true) == 100)
    // Zero steps keep the value.
    #expect(ExternalBrightness.targetValue(current: 42, maximum: 100, steps: 0, fine: false) == 42)
}

@Test func targetStepIsAtLeastOne() {
    // Small ranges still move: 10 / 16 and 10 / 64 round down to 0, so the step is 1.
    #expect(ExternalBrightness.targetValue(current: 5, maximum: 10, steps: 1, fine: false) == 6)
    #expect(ExternalBrightness.targetValue(current: 5, maximum: 10, steps: -1, fine: true) == 4)
}

@Test func targetIsClamped() {
    #expect(ExternalBrightness.targetValue(current: 98, maximum: 100, steps: 1, fine: false) == 100)
    #expect(ExternalBrightness.targetValue(current: 100, maximum: 100, steps: 1, fine: false) == 100)
    #expect(ExternalBrightness.targetValue(current: 3, maximum: 100, steps: -1, fine: false) == 0)
    #expect(ExternalBrightness.targetValue(current: 0, maximum: 100, steps: -5, fine: true) == 0)
    // A current value above the maximum, as a misbehaving display may report, comes back into range.
    #expect(ExternalBrightness.targetValue(current: 120, maximum: 100, steps: 0, fine: false) == 100)
    // Huge counts do not overflow.
    #expect(ExternalBrightness.targetValue(current: 50, maximum: 100, steps: .max, fine: false) == 100)
    #expect(ExternalBrightness.targetValue(current: 50, maximum: 100, steps: .min, fine: false) == 0)
}

@Test func displaysWithoutServiceAreKnownFromTheLastScan() {
    let reachability = DDCReachability()
    // Before any scan every display may have a service.
    #expect(reachability.mayHaveService(2))
    #expect(reachability.mayHaveService(3))

    // Displays 2 and 3 are online; only 2 was matched to a service (3 is wireless, say).
    reachability.update(online: [2, 3], matched: [CGDirectDisplayID(2)])
    #expect(reachability.mayHaveService(2))
    #expect(!reachability.mayHaveService(3))
    // A display the scan did not see is not ruled out.
    #expect(reachability.mayHaveService(4))

    // The next scan replaces the set.
    reachability.update(online: [2, 3], matched: [CGDirectDisplayID(2), 3])
    #expect(reachability.mayHaveService(3))
}
