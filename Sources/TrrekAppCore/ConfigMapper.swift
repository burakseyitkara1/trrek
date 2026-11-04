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
        if settings.swapSides {
            config.left = .volume
            config.right = .brightness
        } else {
            config.left = .brightness
            config.right = .volume
        }
        config.top = effective(settings.topEdge, backlightAvailable: backlightAvailable)
        config.bottom = effectiveBottomEdge(settings, backlightAvailable: backlightAvailable)
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

    /// The action the bottom edge actually runs: the keyboard backlight becomes media control while its
    /// bridge is unavailable.
    public static func effectiveBottomEdge(_ settings: Settings, backlightAvailable: Bool) -> EdgeAction {
        effective(settings.bottomEdge, backlightAvailable: backlightAvailable)
    }

    /// Video scrubbing is not available yet, so it maps to `.off`.
    private static func effective(_ action: EdgeAction, backlightAvailable: Bool) -> EdgeAction {
        switch action {
        case .scrubVideo: .off
        case .keyboardBacklight where !backlightAvailable: .media
        default: action
        }
    }
}
