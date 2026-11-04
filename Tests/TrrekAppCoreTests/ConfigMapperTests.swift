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

@Test func sideEdgesMapTheirOwnActions() {
    var settings = Settings()
    settings.leftEdge = .volume
    settings.rightEdge = .switchTabs
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
    #expect(config.left == .volume)
    #expect(config.right == .switchTabs)
}

@Test func everyEdgeMapsEveryAction() {
    for action in EdgeAction.allCases {
        for edge in Edge.allCases {
            var settings = Settings()
            settings[edge: edge] = action
            let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
            #expect(config.action(for: edge) == action)
        }
    }
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
    #expect(ConfigMapper.effective(settings.bottomEdge, backlightAvailable: false) == .media)
    #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: false).bottom == .media)
    #expect(ConfigMapper.effective(settings.bottomEdge, backlightAvailable: true) == .keyboardBacklight)
    #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: true).bottom == .keyboardBacklight)
    #expect(ConfigMapper.effective(.volume, backlightAvailable: false) == .volume)
}

@Test func keyboardBacklightFallsBackToMediaOnEveryEdge() {
    for edge in Edge.allCases {
        var settings = Settings()
        settings[edge: edge] = .keyboardBacklight
        #expect(ConfigMapper.engineConfig(from: settings, backlightAvailable: false).action(for: edge) == .media)
        let available = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
        #expect(available.action(for: edge) == .keyboardBacklight)
    }
}

@Test func sensitivityScalesEveryStepDistance() {
    let expected: [(SlideSensitivity, Float)] = [
        (.veryLow, 1.6), (.low, 1.25), (.standard, 1.0), (.high, 0.8), (.veryHigh, 0.6)
    ]
    #expect(expected.map(\.0) == SlideSensitivity.allCases)
    #expect(Settings().slideSensitivity == .standard)
    let base = Thresholds()
    var settings = Settings()
    settings.edgeWidth = .wide
    for (sensitivity, multiplier) in expected {
        #expect(sensitivity.multiplier == multiplier)
        settings.slideSensitivity = sensitivity
        let scaled = ConfigMapper.engineConfig(from: settings, backlightAvailable: true).thresholds
        #expect(scaled.stepMM == base.stepMM * multiplier)
        #expect(scaled.appSwitchStepMM == base.appSwitchStepMM * multiplier)
        #expect(scaled.scrubStepMM == base.scrubStepMM * multiplier)
        #expect(scaled.mediaSkipStepMM == base.mediaSkipStepMM * multiplier)
        #expect(scaled.tabSwitchStepMM == base.tabSwitchStepMM * multiplier)
        #expect(scaled.desktopSwitchStepMM == base.desktopSwitchStepMM * multiplier)
        #expect(scaled.zoomStepMM == base.zoomStepMM * multiplier)
        #expect(scaled.undoRedoStepMM == base.undoRedoStepMM * multiplier)
        // Only step distances scale: the slide start, the strip width and the timings keep their values.
        var unscaled = scaled
        unscaled.stepMM = base.stepMM
        unscaled.appSwitchStepMM = base.appSwitchStepMM
        unscaled.scrubStepMM = base.scrubStepMM
        unscaled.mediaSkipStepMM = base.mediaSkipStepMM
        unscaled.tabSwitchStepMM = base.tabSwitchStepMM
        unscaled.desktopSwitchStepMM = base.desktopSwitchStepMM
        unscaled.zoomStepMM = base.zoomStepMM
        unscaled.undoRedoStepMM = base.undoRedoStepMM
        var reference = base
        reference.edgeWidthMM = EdgeWidth.wide.millimetres
        #expect(unscaled == reference)
    }
}

@Test func newActionStepDistancesMatchSpec() {
    let thresholds = Thresholds()
    #expect(Geometry.stepMM(for: .switchTabs, thresholds: thresholds) == 12)
    #expect(Geometry.stepMM(for: .switchDesktops, thresholds: thresholds) == 20)
    #expect(Geometry.stepMM(for: .zoom, thresholds: thresholds) == 8)
    #expect(Geometry.stepMM(for: .undoRedo, thresholds: thresholds) == 10)
}

@Test func shortestScaledStepStaysWellAboveTheEngineTolerance() {
    // The engine treats a step at or below 0.001 mm as no step; the most sensitive setting must stay far above it.
    var settings = Settings()
    settings.slideSensitivity = .veryHigh
    let thresholds = ConfigMapper.engineConfig(from: settings, backlightAvailable: true).thresholds
    let shortest = EdgeAction.allCases.filter { $0 != .off }.map { Geometry.stepMM(for: $0, thresholds: thresholds) }
        .min() ?? 0
    #expect(shortest == Thresholds().stepMM * 0.6)
    #expect(shortest > 2)
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

@Test func scrubVideoIsMappedWhenTrusted() {
    var settings = Settings()
    settings.topEdge = .scrubVideo
    settings.bottomEdge = .scrubVideo
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true)
    #expect(config.top == .scrubVideo)
    #expect(config.bottom == .scrubVideo)
}

@Test func scrubVideoIsOffWhenUntrusted() {
    var settings = Settings()
    settings.topEdge = .scrubVideo
    settings.bottomEdge = .scrubVideo
    let config = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
    #expect(config.top == .off)
    #expect(config.bottom == .off)
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

@Test func untrustedTurnsOffNewActionsOnEveryEdgeAndCorner() {
    let newEdgeActions: [EdgeAction] = [.switchTabs, .switchDesktops, .zoom, .undoRedo]
    for action in newEdgeActions {
        var settings = Settings()
        for edge in Edge.allCases {
            settings[edge: edge] = action
        }
        let untrusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
        #expect(Edge.allCases.allSatisfy { untrusted.action(for: $0) == .off })
        let trusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: true)
        #expect(Edge.allCases.allSatisfy { trusted.action(for: $0) == action })
    }
    // The keyboard backlight on a side edge still works without Accessibility.
    var backlight = Settings()
    backlight.leftEdge = .keyboardBacklight
    let gatedBacklight = ConfigMapper.engineConfig(
        from: backlight,
        backlightAvailable: true,
        accessibilityTrusted: false
    )
    #expect(gatedBacklight.left == .keyboardBacklight)

    for action in CornerAction.allCases {
        var settings = Settings()
        for corner in Corner.allCases {
            settings[corner: corner] = action
        }
        let untrusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: false)
        #expect(Corner.allCases.allSatisfy { untrusted.action(for: $0) == .off })
        let trusted = ConfigMapper.engineConfig(from: settings, backlightAvailable: true, accessibilityTrusted: true)
        #expect(Corner.allCases.allSatisfy { trusted.action(for: $0) == action })
    }
}
