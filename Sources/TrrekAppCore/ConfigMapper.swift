import TrrekEngine
import TrrekPlatform

/// Turns user settings into the engine configuration.
public enum ConfigMapper {
    /// Without Accessibility trust, everything that posts synthetic events or needs an event tap is turned off:
    /// every edge action except the keyboard backlight (which trrek sets directly), every corner action, middle
    /// click and cursor freezing. Posted events are not delivered without the permission.
    public static func engineConfig(
        from settings: Settings,
        backlightAvailable: Bool,
        accessibilityTrusted: Bool = true
    ) -> EngineConfig {
        var config = EngineConfig()
        config.left = effective(settings.leftEdge, backlightAvailable: backlightAvailable)
        config.right = effective(settings.rightEdge, backlightAvailable: backlightAvailable)
        config.top = effective(settings.topEdge, backlightAvailable: backlightAvailable)
        config.bottom = effective(settings.bottomEdge, backlightAvailable: backlightAvailable)
        config.topLeft = settings.topLeft
        config.topRight = settings.topRight
        config.bottomLeft = settings.bottomLeft
        config.bottomRight = settings.bottomRight
        config.bottomQuarterOnly = settings.bottomQuarterOnly
        config.precision = settings.precision
        config.freezeCursor = settings.freezeCursor
        config.middleClickEnabled = settings.middleClick
        config.holdKeyRequired = settings.holdKey != .none
        config.thresholds.edgeWidthMM = settings.edgeWidth.millimetres
        config.thresholds = scaled(config.thresholds, by: settings.slideSensitivity.multiplier)
        if !accessibilityTrusted {
            config.left = gated(config.left, accessibilityTrusted: false)
            config.right = gated(config.right, accessibilityTrusted: false)
            config.top = gated(config.top, accessibilityTrusted: false)
            config.bottom = gated(config.bottom, accessibilityTrusted: false)
            config.topLeft = .off
            config.topRight = .off
            config.bottomLeft = .off
            config.bottomRight = .off
            config.middleClickEnabled = false
            config.freezeCursor = false
        }
        return config
    }

    /// The edge action that runs with the given trust: only the keyboard backlight works without Accessibility.
    public static func gated(_ action: EdgeAction, accessibilityTrusted: Bool) -> EdgeAction {
        accessibilityTrusted || action == .keyboardBacklight ? action : .off
    }

    /// The corner action that runs with the given trust: corners post events, so none works without Accessibility.
    public static func gated(_ action: CornerAction, accessibilityTrusted: Bool) -> CornerAction {
        accessibilityTrusted ? action : .off
    }

    /// The action an edge actually runs: on any edge, the keyboard backlight becomes media control while its bridge
    /// is unavailable.
    public static func effective(_ action: EdgeAction, backlightAvailable: Bool) -> EdgeAction {
        switch action {
        case .keyboardBacklight where !backlightAvailable: .media
        default: action
        }
    }

    /// `thresholds` with every step distance multiplied by `multiplier` (the slide sensitivity). The other
    /// distances, such as the slide start and the strip width, keep their values.
    static func scaled(_ thresholds: Thresholds, by multiplier: Float) -> Thresholds {
        var scaled = thresholds
        scaled.stepMM *= multiplier
        scaled.appSwitchStepMM *= multiplier
        scaled.scrubStepMM *= multiplier
        scaled.mediaSkipStepMM *= multiplier
        scaled.tabSwitchStepMM *= multiplier
        scaled.desktopSwitchStepMM *= multiplier
        scaled.zoomStepMM *= multiplier
        scaled.undoRedoStepMM *= multiplier
        return scaled
    }
}
