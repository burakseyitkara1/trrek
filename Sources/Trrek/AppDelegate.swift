import AppKit
import TrrekAppCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = Coordinator(store: SettingsStore())
    /// Kept for the windows and the overlay that later read it.
    private(set) var launchOptions = LaunchOptions()

    func applicationDidFinishLaunching(_: Notification) {
        launchOptions = LaunchOptions(arguments: CommandLine.arguments)
        coordinator.start()

        if launchOptions.openSettings {
            coordinator.openSettings(tab: launchOptions.settingsTab)
        }
        if launchOptions.welcome {
            coordinator.showWelcome()
        }
        if launchOptions.demoOverlay {
            appLogger.info("demo overlay requested; not implemented yet")
        }
        if let seconds = launchOptions.quitAfter {
            // One-shot, for screenshots and footprint checks.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        coordinator.terminate()
    }
}
