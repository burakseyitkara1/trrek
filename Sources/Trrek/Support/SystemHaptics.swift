import AppKit
import TrrekEngine
import TrrekPlatform

/// Haptic feedback through the system's generic performer, used when the trackpad actuator cannot be opened.
/// Called on the frame thread; the performer is driven on the main thread.
struct SystemHaptics: HapticPerforming {
    func perform(_ event: HapticEvent, strength: HapticStrength) {
        guard strength != .off else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = event == .step ? .alignment : .levelChange
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }
}
