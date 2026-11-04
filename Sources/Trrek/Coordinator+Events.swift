import AppKit
import TrrekAppCore
import TrrekEngine
import TrrekPlatform

/// Input, system and permission events.
extension Coordinator {
    // MARK: - Multitouch

    /// Starts the multitouch stream and records why it could not start.
    func startPipeline() {
        guard let pipeline else { return }
        do {
            try pipeline.start()
            trackpadIssue = nil
            appLogger.info("multitouch started with \(pipeline.deviceCount, privacy: .public) device(s)")
        } catch {
            trackpadIssue = Self.issue(for: error)
            appLogger.error("multitouch start failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Restarts the multitouch stream once the burst of wake and device notifications has settled: each call
    /// replaces the pending restart, so only the last one within `restartDelay` runs.
    func scheduleRestart(reason: String) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restartPipeline(reason: reason) }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay, execute: work)
    }

    /// Stops frames, releases anything held, forgets modifier state that may have changed unseen (a key-up
    /// missed during sleep) and starts again.
    private func restartPipeline(reason: String) {
        restartWork = nil
        appLogger.info("restarting multitouch after \(reason, privacy: .public)")
        pipeline?.stop()
        dispatcher?.releaseAll()
        // A held key may have been released unseen. Toggle mode keeps its on/off state, which the user set on
        // purpose; only the press in flight is forgotten.
        if holdKeyTracker.mode == .toggle {
            holdKeyTracker.cancelPress()
        } else {
            holdKeyTracker.reset()
        }
        let satisfied = holdKeyTracker.isSatisfied
        pipeline?.withEngine { $0.setHoldKeySatisfied(satisfied) }
        startPipeline()
        statusMenu?.refresh()
    }

    /// The pipeline stopped itself because a first frame was implausible; it stays stopped until the next wake or
    /// device change restarts it.
    func trackpadDataUnavailable() {
        dispatcher?.releaseAll()
        trackpadIssue = .dataUnavailable
        appLogger.error("multitouch stopped: trackpad data unavailable")
        statusMenu?.refresh()
    }

    private static func issue(for error: any Error) -> TrackpadIssue {
        if let error = error as? PipelineError, error == .noDevices {
            return .notFound
        }
        if let error = error as? RawFrameStreamError, error == .noDevices {
            return .notFound
        }
        return .dataUnavailable
    }

    // MARK: - Keyboard

    /// Creates the input monitor on first use and starts it; without Accessibility it stays unavailable until
    /// `trustChanged` starts it again.
    func startInputMonitor() {
        let monitor: InputMonitor
        if let inputMonitor {
            monitor = inputMonitor
        } else {
            monitor = InputMonitor()
            monitor.onKeyDown = { [weak self] uptime in
                MainActor.assumeIsolated { self?.keyDown(at: uptime) }
            }
            monitor.onFlagsChanged = { [weak self] flags, uptime in
                MainActor.assumeIsolated { self?.flagsChanged(flags, at: uptime) }
            }
            monitor.onMouseDown = { [weak self] uptime in
                MainActor.assumeIsolated { self?.holdKeyTracker.handleMouseDown(at: uptime) }
            }
            inputMonitor = monitor
        }
        monitor.start()
        appLogger.info("input monitor available: \(monitor.isAvailable, privacy: .public)")
    }

    private func keyDown(at uptime: TimeInterval) {
        holdKeyTracker.handleKeyDown(at: uptime)
        guard let pipeline, let time = pipeline.engineTime(fromUptime: uptime) else { return }
        pipeline.withEngine { $0.noteKeyDown(at: time) }
    }

    private func flagsChanged(_ flags: CGEventFlags, at uptime: TimeInterval) {
        guard holdKeyTracker.handleFlagsChanged(flags, at: uptime) else { return }
        let satisfied = holdKeyTracker.isSatisfied
        pipeline?.withEngine { $0.setHoldKeySatisfied(satisfied) }
        statusMenu?.refreshIcon()
    }

    // MARK: - System

    func startObservers() {
        frontmostObserver.onChange = { [weak self] bundleID, isOwnApp in
            MainActor.assumeIsolated {
                self?.updatePause(bundleID: bundleID)
                // Scrub sends arrow keys to the front app; while that is trrek's own window it sends none.
                self?.dispatcher?.ownAppFrontmost = isOwnApp
            }
        }
        frontmostObserver.start()
        wakeObserver.onWake = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRestart(reason: "wake") }
        }
        wakeObserver.start()
        hotplugObserver.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRestart(reason: "device change") }
        }
        hotplugObserver.start()
    }

    /// Called only when trust actually changes. On a grant both taps are created anew, since taps made before
    /// a revocation stay invalid; either way the engine gets the config with Accessibility features gated.
    func trustChanged(_ trusted: Bool) {
        isTrusted = trusted
        appLogger.info("accessibility trusted: \(trusted, privacy: .public)")
        if trusted {
            freezer.replace(with: EventTapGuard())
            inputMonitor?.stop()
            inputMonitor = nil
            startInputMonitor()
        }
        let config = engineConfig()
        pipeline?.withEngine { $0.update(config: config) }
        statusMenu?.refresh()
        windows.settingsModel?.accessibilityGranted = trusted
        windows.welcomeModel?.accessibilityGranted = trusted
    }
}
