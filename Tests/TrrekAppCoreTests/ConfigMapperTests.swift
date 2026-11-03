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
    settings.bottomEdge = .switchApps
    settings.middleClick = true
    settings.freezeCursor = true
    settings.topLeft = .mute

    let untrusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
    #expect(untrusted.top == .off)
    #expect(untrusted.bottom == .off)
    #expect(!untrusted.middleClickEnabled)
    #expect(!untrusted.freezeCursor)
    // Features that do not need Accessibility stay as configured.
    #expect(untrusted.left == .brightness)
    #expect(untrusted.right == .volume)
    #expect(untrusted.topLeft == .mute)

    let trusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: true)
    #expect(trusted.top == .switchApps)
    #expect(trusted.bottom == .switchApps)
    #expect(trusted.middleClickEnabled)
    #expect(trusted.freezeCursor)

    var media = Settings()
    media.topEdge = .media
    #expect(ConfigMapper.engineConfig(from: media, backlightAvailable: true, accessibilityTrusted: false).top == .media)
}
