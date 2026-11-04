import Testing
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

@Test func defaultMappingMatchesSpec() {
    let config = ConfigMapper.engineConfig(from: Settings(), backlightAvailable: true)
    #expect(config.left == .brightness)
    #expect(config.right == .volume)
    #expect(config.top == .switchApps)
    #expect(config.bottom == .keyboardBacklight)
    #expect([config.topLeft, config.topRight, config.bottomLeft, config.bottomRight] == [.off, .off, .off, .off])
    #expect(!config.precision)
    #expect(config.freezeCursor)
    #expect(!config.bottomQuarterOnly)
    #expect(!config.middleClickEnabled)
    #expect(!config.holdKeyRequired)
    #expect(config.thresholds.edgeWidthMM == 10)
    #expect(config == EngineConfig())
}

@Test func swapSidesSwapsLeftRight() {
    var settings = Settings()
    settings.swapSides = true
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
    #expect(config.left == .volume)
    #expect(config.right == .brightness)
}

@Test func edgeWidthMapsToMillimetres() {
    var settings = Settings()
    let expected: [(EdgeWidth, Float)] = [(.narrow, 7), (.standard, 10), (.wide, 14)]
    for (width, millimetres) in expected {
        #expect(width.millimetres == millimetres)
        settings.edgeWidth = width
        let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
        #expect(config.thresholds.edgeWidthMM == millimetres)
    }
}

@Test func bottomEdgeFallsBackToMediaWithoutBacklight() {
    let settings = Settings()
    #expect(ConfigMapper.effectiveBottomEdge(settings, backlightAvailable: false) == .media)
    #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: false).bottom == .media)
    #expect(ConfigMapper.effectiveBottomEdge(settings, backlightAvailable: true) == .keyboardBacklight)
    #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: true).bottom == .keyboardBacklight)

    var media = Settings()
    media.bottomEdge = .volume
    #expect(ConfigMapper.effectiveBottomEdge(media, backlightAvailable: false) == .volume)
}

@Test func holdKeyNoneDoesNotRequireKey() {
    var settings = Settings()
    settings.holdKey = .none
    #expect(!ConfigMapper.engineConfig(from: settings, backlightAvailable: true).holdKeyRequired)
    for key in HoldKey.allCases where key != .none {
        settings.holdKey = key
        #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: true).holdKeyRequired)
    }
}

@Test func scrubVideoIsOffInPhaseOne() {
    var settings = Settings()
    settings.topEdge = .scrubVideo
    settings.bottomEdge = .scrubVideo
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
    #expect(config.top == .off)
    #expect(config.bottom == .off)
    #expect(ConfigMapper.effectiveBottomEdge(settings, backlightAvailable: true) == .off)
}

@Test func remainingFieldsAreCopied() {
    var settings = Settings()
    settings.topLeft = .mute
    settings.topRight = .screenshot
    settings.bottomLeft = .screenshot
    settings.bottomRight = .mute
    settings.precision = true
    settings.freezeCursor = false
    settings.bottomQuarterOnly = true
    settings.middleClick = true
    settings.topEdge = .media
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
    #expect(config.topLeft == .mute)
    #expect(config.topRight == .screenshot)
    #expect(config.bottomLeft == .screenshot)
    #expect(config.bottomRight == .mute)
    #expect(config.precision)
    #expect(!config.freezeCursor)
    #expect(config.bottomQuarterOnly)
    #expect(config.middleClickEnabled)
    #expect(config.top == .media)
}

@Test func untrustedDisablesAccessibilityFeatures() {
    var settings = Settings()
    settings.topEdge = .switchApps
    settings.bottomEdge = .media
    settings.middleClick = true
    settings.freezeCursor = true
    settings.topLeft = .mute
    settings.topRight = .screenshot
    settings.bottomLeft = .mute
    settings.bottomRight = .screenshot

    // Everything that posts synthetic events is off: every edge but the keyboard backlight, every corner, middle
    // click and cursor freezing.
    let untrusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
    #expect(untrusted.left == .off)
    #expect(untrusted.right == .off)
    #expect(untrusted.top == .off)
    #expect(untrusted.bottom == .off)
    #expect(untrusted.topLeft == .off)
    #expect(untrusted.topRight == .off)
    #expect(untrusted.bottomLeft == .off)
    #expect(untrusted.bottomRight == .off)
    #expect(!untrusted.middleClickEnabled)
    #expect(!untrusted.freezeCursor)

    let trusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(trusted.left == .brightness)
    #expect(trusted.right == .volume)
    #expect(trusted.top == .switchApps)
    #expect(trusted.bottom == .media)
    #expect(trusted.topLeft == .mute)
    #expect(trusted.bottomRight == .screenshot)
    #expect(trusted.middleClickEnabled)
    #expect(trusted.freezeCursor)
}

@Test func untrustedKeepsOnlyTheKeyboardBacklight() {
    var settings = Settings()
    settings.topEdge = .keyboardBacklight
    settings.bottomEdge = .keyboardBacklight
    let untrusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
    #expect(untrusted.top == .keyboardBacklight)
    #expect(untrusted.bottom == .keyboardBacklight)

    // Without the backlight bridge the edge runs media control, which posts events and is gated.
    let noBridge = ConfigMapper.engineConfig(from: settings, backlightAvailable: false, accessibilityTrusted: false)
    #expect(noBridge.bottom == .off)

    for action in EdgeAction.allCases where action != .keyboardBacklight {
        #expect(ConfigMapper.gated(action, accessibilityTrusted: false) == .off)
        #expect(ConfigMapper.gated(action, accessibilityTrusted: true) == action)
    }
    #expect(ConfigMapper.gated(.keyboardBacklight, accessibilityTrusted: false) == .keyboardBacklight)
    #expect(ConfigMapper.gated(CornerAction.mute, accessibilityTrusted: false) == .off)
    #expect(ConfigMapper.gated(CornerAction.mute, accessibilityTrusted: true) == .mute)
}
