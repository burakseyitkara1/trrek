import CMultitouch
import Dispatch
import Foundation
import os
import TrrekEngine

public enum PipelineError: Error {
    case noDevices
}

/// What `GesturePipeline.onDataUnavailable` reports.
public enum PipelineIssue: Sendable {
    /// A device's first frame had contact states, positions or sizes outside any plausible range: the contact
    /// layout the framework delivers is not the one trrek reads.
    case dataUnavailable
}

/// Feeds raw multitouch frames into a `GestureEngine`.
///
/// Thread model:
/// - Frames arrive on the framework's callback thread. Each is converted on the stack and handed to the engine
///   under one `os_unfair_lock`; the engine's commands reach its sink synchronously inside that lock.
/// - Every other engine call (`noteKeyDown`, `setHoldKeySatisfied`, `setPaused`, `update(config:)`, `reset()`)
///   must go through `withEngine`, which takes the same lock. The lock is not recursive: neither the sink nor a
///   `withEngine` body may call back into the pipeline.
/// - `start()`, `stop()` and `restart()` are called from one thread (the main thread in the app).
/// - The first frame with touching contacts (or a contact in an unknown state) from each device is checked for
///   known contact states and plausible positions and sizes; a failure stops the pipeline on the main thread and is
///   reported through `onDataUnavailable`.
///
/// Clocks: frame timestamps come from each device's own clock, which matches no system clock and may differ
/// between devices. The pipeline remembers, per device, the last frame timestamp and the system uptime at
/// which it arrived; `engineTime(fromUptime:)` and the watchdog translate uptime into the frame clock of the
/// device that is driving the engine.
///
/// While a slide is active (`sliding` or `lost`) a one-shot watchdog fires the engine's current `lostTimeout` after
/// the active device's last frame and calls `engine.tick(now:)`, and a user-initiated activity keeps the process out
/// of App Nap. Idle, the pipeline schedules nothing.
public final class GesturePipeline: @unchecked Sendable {
    struct DeviceEntry {
        let ref: MTDeviceRef
        let id: UInt64
        let geometry: DeviceGeometry
        /// The last frame's own timestamp and the uptime at which it arrived; `nil` until the first frame.
        var lastFrame: (timestamp: TimeInterval, uptime: TimeInterval)?
        /// Whether a frame with touching contacts passed the sanity check; only the first such frame is checked.
        var checked = false

        /// `uptime` translated into this device's frame clock, once a frame has been seen.
        func frameTime(atUptime uptime: TimeInterval) -> TimeInterval? {
            lastFrame.map { $0.timestamp + (uptime - $0.uptime) }
        }
    }

    /// Fixed-capacity device table, searched linearly on every frame; never allocates.
    struct DeviceTable {
        static let capacity = 4

        private var entries = InlineArray<4, DeviceEntry?>(repeating: nil)
        private(set) var count = 0

        mutating func append(_ entry: DeviceEntry) -> Bool {
            guard count < Self.capacity else { return false }
            entries[count] = entry
            count += 1
            return true
        }

        func index(of ref: MTDeviceRef) -> Int? {
            for index in 0 ..< count where entries[index]?.ref == ref {
                return index
            }
            return nil
        }

        subscript(_ index: Int) -> DeviceEntry? {
            get { index < count ? entries[index] : nil }
            set {
                guard index < count else { return }
                entries[index] = newValue
            }
        }
    }

    /// Shortest delay used when the watchdog re-arms itself for the rest of a timeout.
    private static let minimumRearm: TimeInterval = 0.005

    private let engine: GestureEngine
    /// System uptime in seconds (`GesturePipeline.uptime()`); injected so tests can fire the watchdog at a known time.
    private let clock: @Sendable () -> TimeInterval
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let watchdog: DispatchSourceTimer

    // The properties below, up to `stream`, are guarded by `lock`.

    private var table = DeviceTable()
    /// Table index of the device whose frame made the slide active; `nil` while no slide is active.
    private var activeIndex: Int?
    /// Table index of the device that delivered the most recent frame.
    private var latestIndex: Int?
    private var watchdogArmed = false
    private var activity: NSObjectProtocol?
    /// Counts `start()` calls, so a report about an earlier stream never stops a newer one.
    fileprivate var generation = 0

    // Touched only by the thread that calls `start()`/`stop()`.
    private var stream: RawFrameStream?
    public private(set) var isRunning = false
    /// The devices streaming since the last successful `start()`; empty while stopped. Read it on the thread that
    /// calls `start()`, for example to open each trackpad's haptic actuator.
    public private(set) var devices: [MultitouchDeviceInfo] = []

    /// Called on the main thread after the pipeline stopped itself because a device's first frame failed the
    /// sanity check. Set it on the main thread before `start()`.
    public var onDataUnavailable: (@Sendable (PipelineIssue) -> Void)?

    /// `clock` reads system uptime; tests inject a fixed one.
    public init(engine: GestureEngine, clock: @escaping @Sendable () -> TimeInterval = GesturePipeline.uptime) {
        self.engine = engine
        self.clock = clock
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        watchdog = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.burakseyitkara.trrek.watchdog", qos: .userInitiated)
        )
        watchdog.setEventHandler { [weak self] in
            self?.watchdogFired()
        }
        watchdog.schedule(deadline: .distantFuture)
        watchdog.activate()
    }

    deinit {
        // Releases a frozen cursor, the activity assertion and the watchdog deadline.
        stop()
        watchdog.cancel()
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Number of devices currently feeding the engine.
    public var deviceCount: Int {
        locked { table.count }
    }

    /// Enumerates the multitouch devices and starts streaming from the trackpads. Throws
    /// `PipelineError.noDevices` when there is no usable trackpad, or the stream's error when no device could be
    /// started. Restarts when already running.
    public func start() throws {
        // Stop first: enumeration releases the previous device list, which the old stream still refers to.
        stop()
        locked { generation += 1 }
        let selected = install(devices: MultitouchDevices.enumerate())
        guard !selected.isEmpty else { throw PipelineError.noDevices }

        let stream = RawFrameStream(devices: selected)
        stream.onFrame = { [weak self] device, touches, timestamp in
            guard let self else { return }
            handleFrame(device, touches, timestamp, uptime: clock())
        }
        do {
            try stream.start()
        } catch {
            locked { table = DeviceTable() }
            throw error
        }
        self.stream = stream
        devices = selected
        isRunning = true
    }

    /// Stops streaming and returns the engine to idle (an active slide only releases the cursor).
    public func stop() {
        stream?.stop()
        stream = nil
        devices = []
        locked {
            // A frame still in flight finds an empty table and is dropped.
            table = DeviceTable()
            latestIndex = nil
            engine.reset()
            settle(frameIndex: nil)
        }
        isRunning = false
    }

    /// Stops and starts again, for example after wake or a device change. Failures are logged.
    public func restart() {
        do {
            try start()
        } catch {
            platformLogger.error("pipeline restart failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Runs `body` with exclusive access to the engine, under the same lock that guards frame processing.
    public func withEngine<T>(_ body: (GestureEngine) -> T) -> T {
        locked {
            let result = body(engine)
            settle(frameIndex: nil)
            return result
        }
    }

    /// Converts a system-uptime timestamp into the engine's clock, which is the frame clock of the device that
    /// drives the active gesture (the device of the most recent frame when idle).
    ///
    /// `uptime` is in seconds since boot, not counting sleep: `ProcessInfo.processInfo.systemUptime`, as the
    /// input monitor reports for each event's arrival. Returns `nil` until a frame has been seen since the last
    /// `start()`. Use it for every time handed to the engine from outside, such as `noteKeyDown(at:)`.
    public func engineTime(fromUptime uptime: TimeInterval) -> TimeInterval? {
        locked {
            guard let index = activeIndex ?? latestIndex else { return nil }
            return table[index]?.frameTime(atUptime: uptime)
        }
    }

    // MARK: - Devices and frames (internal for tests)

    /// Builds the device table from `devices` and returns the devices that made it in: trackpads (and devices of
    /// unknown kind) with a surface size, at most `DeviceTable.capacity`. Other multitouch devices, such as a
    /// mouse with a touch surface, are skipped.
    func install(devices: [MultitouchDeviceInfo]) -> [MultitouchDeviceInfo] {
        var newTable = DeviceTable()
        var selected: [MultitouchDeviceInfo] = []
        for device in devices {
            guard device.kind != .other else {
                platformLogger.info("skipping multitouch device that is not a trackpad")
                continue
            }
            let geometry = DeviceGeometry(
                widthMM: device.widthMM,
                heightMM: device.heightMM,
                isBuiltIn: device.isBuiltIn
            )
            guard geometry.isValid else {
                platformLogger.error("skipping multitouch device without a surface size")
                continue
            }
            let id = Self.deviceID(of: device.ref)
            guard newTable.append(DeviceEntry(ref: device.ref, id: id, geometry: geometry)) else {
                platformLogger.error("more than \(DeviceTable.capacity, privacy: .public) devices; ignoring the rest")
                break
            }
            selected.append(device)
        }
        locked {
            table = newTable
            activeIndex = nil
            latestIndex = nil
        }
        return selected
    }

    /// Handles one frame; `uptime` is when it arrived. Runs on the frame thread and never allocates, except once
    /// when a device's first frame with touching contacts fails the sanity check.
    func handleFrame(
        _ device: MTDeviceRef,
        _ touches: UnsafeBufferPointer<MTTouch>,
        _ timestamp: Double,
        uptime: TimeInterval
    ) {
        os_unfair_lock_lock(lock)
        let rejected = process(device, touches, timestamp, uptime: uptime)
        let rejectedGeneration = generation
        os_unfair_lock_unlock(lock)
        if rejected {
            reportDataUnavailable(generation: rejectedGeneration)
        }
    }

    /// The frame work under `lock`. Returns `true` when the frame was the device's first with touching contacts
    /// and failed the sanity check: the device table is then emptied, so this and every later frame are dropped.
    private func process(
        _ device: MTDeviceRef,
        _ touches: UnsafeBufferPointer<MTTouch>,
        _ timestamp: Double,
        uptime: TimeInterval
    ) -> Bool {
        guard let index = table.index(of: device), var entry = table[index] else { return false }
        // A state outside the known ones triggers the check too: with a drifted layout no contact may read as touching.
        if !entry.checked, FrameConverter.hasTouchingContact(touches) || FrameConverter.hasInvalidState(touches) {
            guard FrameConverter.isPlausible(touches) else {
                table = DeviceTable()
                latestIndex = nil
                return true
            }
            entry.checked = true
        }
        entry.lastFrame = (timestamp, uptime)
        table[index] = entry
        latestIndex = index
        engine.process(FrameConverter.frame(
            touches: touches,
            timestamp: timestamp,
            deviceID: entry.id,
            geometry: entry.geometry
        ))
        settle(frameIndex: index)
        return false
    }

    /// The device ID the engine reports with each command (`CommandSink.handle(_:device:)`) for frames from `ref`.
    public static func deviceID(of ref: MTDeviceRef) -> UInt64 {
        UInt64(UInt(bitPattern: ref))
    }

    /// Seconds since boot, not counting sleep (the clock of `ProcessInfo.systemUptime`). A plain clock read,
    /// safe on the frame thread.
    public static func uptime() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }

    // MARK: - Watchdog and activity

    /// The watchdog's handler (internal so tests can fire it): ticks the engine with the current time in the frame
    /// clock of the device driving the slide.
    func watchdogFired() {
        locked {
            watchdogArmed = false
            let index = activeIndex ?? latestIndex
            if isActive(engine.stateKind), let now = index.flatMap({ table[$0]?.frameTime(atUptime: clock()) }) {
                engine.tick(now: now)
            }
            settle(frameIndex: nil)
        }
    }

    // Call the functions below with `lock` held.

    /// Brings the active device, the activity assertion and the watchdog in line with the engine state.
    /// `frameIndex` is the device of the frame just processed, or `nil` outside frame handling.
    ///
    /// The watchdog is armed once when a slide becomes active and re-arms itself for the remainder of the
    /// timeout when the active device kept sending frames, so it fires `lostTimeout` after that device's last
    /// frame without being rescheduled on every frame (rescheduling a dispatch timer allocates). Frames from
    /// other devices never move the deadline. The timeout is read from the engine's configuration each time the
    /// watchdog is armed, so a configuration update applies to the next slide.
    private func settle(frameIndex: Int?) {
        let kind = engine.stateKind
        let active = isActive(kind)
        if active {
            // A slide only becomes active while processing a frame of the device it runs on.
            if activeIndex == nil {
                activeIndex = frameIndex
            }
        } else {
            activeIndex = nil
        }
        if kind == .sliding, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "trrek slide")
        } else if !active, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
        if active, !watchdogArmed {
            let timeout = engine.lostTimeout
            var delay = timeout
            if let index = activeIndex, let last = table[index]?.lastFrame {
                delay = max(timeout - (clock() - last.uptime), Self.minimumRearm)
            }
            watchdog.schedule(deadline: .now() + delay)
            watchdogArmed = true
        } else if !active, watchdogArmed {
            watchdog.schedule(deadline: .distantFuture)
            watchdogArmed = false
        }
    }

    private func isActive(_ kind: StateKind) -> Bool {
        kind == .sliding || kind == .lost
    }

    fileprivate func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return body()
    }
}

private extension GesturePipeline {
    /// Stops the pipeline on the main thread and reports the issue, unless it was restarted in the meantime.
    func reportDataUnavailable(generation reported: Int) {
        platformLogger.error("multitouch data out of range on the first frame; stopping")
        DispatchQueue.main.async { [weak self] in
            guard let self, locked({ self.generation == reported }) else { return }
            stop()
            onDataUnavailable?(.dataUnavailable)
        }
    }
}
