import AppKit
import TrrekAppCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = Coordinator(store: SettingsStore())
    /// Kept for the windows and the overlay that later read it.
    private(set) var launchOptions = LaunchOptions()
    /// Quits cleanly on SIGTERM and SIGINT, so Command is never left held down.
    private var terminationSignals: TerminationSignals?

    func applicationDidFinishLaunching(_: Notification) {
        launchOptions = LaunchOptions(arguments: CommandLine.arguments)
        coordinator.start(skipFirstRun: launchOptions.skipFirstRun)
        terminationSignals = TerminationSignals { [coordinator] number in
            MainActor.assumeIsolated {
                appLogger.info("signal \(number, privacy: .public); quitting")
                coordinator.terminate()
            }
            exit(0)
        }

        if launchOptions.openSettings {
            coordinator.openSettings(tab: launchOptions.settingsTab)
        }
        if launchOptions.welcome {
            coordinator.showWelcome()
        }
        if launchOptions.demoOverlay {
            coordinator.showDemoOverlay()
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

    /// Opening the app again while it runs (for example from the Applications folder) shows the settings window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        coordinator.openSettings()
        return false
    }

    func applicationWillTerminate(_: Notification) {
        coordinator.terminate()
    }
}
