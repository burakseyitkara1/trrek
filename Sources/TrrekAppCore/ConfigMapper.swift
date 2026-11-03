import TrrekEngine
import TrrekPlatform

/// Turns user settings into the engine configuration.
public enum ConfigMapper {
    /// Without Accessibility trust, the features that rely on event taps or posted keyboard and mouse events
    /// (app switching, middle click, cursor freezing) are turned off.
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
            if config.top == .switchApps {
                config.top = .off
            }
            if config.bottom == .switchApps {
                config.bottom = .off
            }
            config.middleClickEnabled = false
            config.freezeCursor = false
        }
        return config
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
