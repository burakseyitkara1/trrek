import CoreGraphics
import Foundation
import IOKit
import Synchronization

/// Why a DDC/CI transfer failed.
public enum DDCError: Error, Equatable, CustomStringConvertible {
    /// No audio/video service was matched to the display.
    case noService
    case writeFailed(IOReturn)
    case readFailed(IOReturn)
    /// The display answered, but not with a valid reply (corrupt, or the control is unsupported).
    case invalidReply

    public var description: String {
        switch self {
        case .noService: "no DDC service for this display"
        case let .writeFailed(code): String(format: "I2C write failed (0x%08x)", code)
        case let .readFailed(code): String(format: "I2C read failed (0x%08x)", code)
        case .invalidReply: "no valid reply"
        }
    }
}

/// Steps the brightness of external displays over DDC/CI.
///
/// The I/O Registry's external `DCPAVServiceProxy` entries are paired with the online external displays by
/// `DisplayServiceMatcher`. The pairing is redone when the set of external displays changes, after a display
/// reconfiguration (plug, unplug, wake; reported by the window server, no polling), and at the next slide after a
/// failed transfer (at most every `failureRescanInterval`), since a replugged display keeps its ID but gets a new
/// service. A display's maximum is read once; its current value is read again when a step follows a pause (a new
/// slide), since the display's own buttons may have changed it. After a failure, steps fail at once until the next
/// slide, so a display without DDC/CI is not asked again on every step.
///
/// An external display that the last scan found no service for (a wireless or virtual display, for example) is not
/// treated as external: its steps take the brightness media key, as on a Mac without DDC. The services are scanned
/// once at creation and after each display reconfiguration, in the background, so this is known before the first
/// slide. A failure is logged once when a display enters it, not on every step.
///
/// The I2C transfers wait on the bus with `usleep`, so `step` must only run on a background serial queue. Calls are
/// serialized by an internal lock.
public final class ExternalBrightness: ExternalBrightnessControlling, @unchecked Sendable {
    /// A step after this long without one starts a new slide and reads the current value again.
    static let rereadInterval: TimeInterval = 1.5
    /// The shortest time between two registry scans caused by failed transfers.
    static let failureRescanInterval: TimeInterval = 5

    private struct Display {
        let service: DDCService
        var maximum: UInt16?
        var current: UInt16?
        var lastStep: TimeInterval = -.infinity
        /// The last step's failure; until the next slide, steps fail at once without touching the bus.
        var failure: DDCError?
    }

    /// A display and the service it was matched to, for diagnostics.
    public struct Pairing: Sendable {
        public let display: DisplayDescriptor
        public let service: ServiceDescriptor?
        public let serviceIndex: Int?
    }

    private let symbols: AVServiceSymbols
    private let lock = NSLock()
    /// Set by the display reconfiguration callback (on the main thread) without taking `lock`, which a transfer
    /// may hold for a while; the next call rescans.
    fileprivate let configurationChanged = Atomic(false)
    private var displays: [CGDirectDisplayID: Display] = [:]
    private var services: [ServiceDescriptor] = []
    /// The external displays online when the services were last matched; `nil` forces a new match.
    private var matchedFor: [CGDirectDisplayID]?
    private var lastFailureRescan: TimeInterval = -.infinity
    /// The displays the last scan found without a service; read on the frame thread.
    let reachability = DDCReachability()
    /// A background scan is queued and has not started yet.
    private let scanScheduled = Atomic(false)
    /// The failure last logged for each display; cleared by a successful step.
    private var loggedFailures: [CGDirectDisplayID: DDCError] = [:]

    /// `nil` when the display service symbols are unavailable on this system.
    public init?() {
        guard let symbols = PrivateSymbols.avService else { return nil }
        self.symbols = symbols
        let result = CGDisplayRegisterReconfigurationCallback(
            displayReconfigured, Unmanaged.passUnretained(self).toOpaque()
        )
        if result != .success {
            let code = result.rawValue
            platformLogger.error("display reconfiguration callback not registered: \(code, privacy: .public)")
        }
        scheduleScan()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    /// External and not known to lack a service. Takes no lock that a transfer holds, so it never waits on the bus.
    public func isExternal(display: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(display) == 0 && reachability.mayHaveService(display)
    }

    public func step(display: CGDirectDisplayID, direction: Int, fine: Bool) -> Float? {
        lock.withLock {
            switch stepLocked(display: display, steps: direction, fine: fine) {
            case let .success(level):
                loggedFailures[display] = nil
                return level
            case let .failure(error):
                if loggedFailures[display] != error {
                    loggedFailures[display] = error
                    platformLogger.error("external brightness step failed: \(error.description, privacy: .public)")
                }
                return nil
            }
        }
    }

    /// Matches the services again on a background queue, unless a scan is already queued.
    fileprivate func scheduleScan() {
        guard !scanScheduled.exchange(true, ordering: .relaxed) else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            scanScheduled.store(false, ordering: .relaxed)
            lock.withLock { refreshIfNeeded() }
        }
    }

    /// The new raw value after `steps` steps from `current`: a step is 1/16 of `maximum` (1/64 when fine), at
    /// least 1, and the result stays within 0...maximum.
    public static func targetValue(current: UInt16, maximum: UInt16, steps: Int, fine: Bool) -> UInt16 {
        let size = max(1, Int(maximum) / (fine ? 64 : 16))
        // A step is at least 1, so `maximum` steps reach either end; limiting the count rules out overflow.
        let count = min(max(steps, -Int(maximum)), Int(maximum))
        return UInt16(min(Int(maximum), max(0, Int(current) + count * size)))
    }

    /// The online external displays and the services they were matched to.
    public func pairings() -> (pairings: [Pairing], serviceCount: Int) {
        lock.withLock {
            refreshIfNeeded()
            let matched = matchedFor ?? []
            let indices = DisplayServiceMatcher.match(
                displays: matched.map(DisplayDescriptor.init(display:)),
                services: services
            )
            let pairings = matched.map { id in
                Pairing(
                    display: DisplayDescriptor(display: id),
                    service: indices[id].map { services[$0] },
                    serviceIndex: indices[id]
                )
            }
            return (pairings, services.count)
        }
    }

    /// Reads `display`'s brightness from the display, recording every exchange: up to `readAttempts` with the
    /// read offset 0x51, then, if none gave a valid reply, up to `readAttempts` with offset 0.
    public func diagnoseRead(display: CGDirectDisplayID) -> Result<[DDCReadAttempt], DDCError> {
        lock.withLock {
            refreshIfNeeded()
            guard let service = displays[display]?.service else { return .failure(.noService) }
            var attempts: [DDCReadAttempt] = []
            for offset in [DDCPacket.sourceAddress, 0] {
                for _ in 0 ..< DDCService.readAttempts {
                    if !attempts.isEmpty {
                        usleep(DDCService.replyDelay)
                    }
                    let attempt = service.exchange(readOffset: offset)
                    attempts.append(attempt)
                    if attempt.value != nil {
                        return .success(attempts)
                    }
                }
            }
            return .success(attempts)
        }
    }

    // MARK: - Steps

    private func stepLocked(display: CGDirectDisplayID, steps: Int, fine: Bool) -> Result<Float, DDCError> {
        let now = ProcessInfo.processInfo.systemUptime
        refreshIfNeeded()
        if let failed = displays[display], let failure = failed.failure {
            if now - failed.lastStep <= Self.rereadInterval {
                displays[display]?.lastStep = now
                return .failure(failure)
            }
            // A new slide after a failure: the service may be stale (replugged or woken), so scan again first.
            if now - lastFailureRescan >= Self.failureRescanInterval {
                lastFailureRescan = now
                matchedFor = nil
                refreshIfNeeded()
            }
        }
        guard var entry = displays[display] else { return .failure(.noService) }
        let result = transfer(&entry, steps: steps, fine: fine, now: now)
        entry.lastStep = ProcessInfo.processInfo.systemUptime
        switch result {
        case .success:
            entry.failure = nil
        case let .failure(error):
            entry.failure = error
            entry.current = nil
        }
        displays[display] = entry
        return result
    }

    /// Reads the display when needed, then writes the new value. `now` is when the step began.
    private func transfer(
        _ entry: inout Display,
        steps: Int,
        fine: Bool,
        now: TimeInterval
    ) -> Result<Float, DDCError> {
        if entry.maximum == nil || entry.current == nil || now - entry.lastStep > Self.rereadInterval {
            switch entry.service.read() {
            case let .success(value):
                entry.current = value.current
                entry.maximum = value.maximum
            case let .failure(error):
                return .failure(error)
            }
        }
        guard let maximum = entry.maximum, maximum > 0, let current = entry.current else {
            return .failure(.invalidReply)
        }
        let target = Self.targetValue(current: current, maximum: maximum, steps: steps, fine: fine)
        if target != current {
            let result = entry.service.send(DDCPacket.setVCP(DDCPacket.brightnessCode, value: target))
            guard result == kIOReturnSuccess else { return .failure(.writeFailed(result)) }
            usleep(DDCService.writeDelay)
        }
        entry.current = target
        return .success(Float(target) / Float(maximum))
    }

    // MARK: - Matching

    /// Matches the services to the displays again when the set of online external displays changed, the displays
    /// were reconfigured, or a rescan was requested.
    private func refreshIfNeeded() {
        if configurationChanged.exchange(false, ordering: .relaxed) {
            matchedFor = nil
        }
        let online = DisplayRegistry.onlineExternalDisplays()
        guard online != matchedFor else { return }
        matchedFor = online
        let found = DisplayRegistry.externalServices(symbols: symbols)
        services = found.map(\.descriptor)
        let indices = DisplayServiceMatcher.match(
            displays: online.map(DisplayDescriptor.init(display:)),
            services: services
        )
        displays = indices.mapValues { Display(service: found[$0].service) }
        reachability.update(online: online, matched: indices.keys)
        let serviceCount = found.count
        platformLogger.info("external displays: \(online.count, privacy: .public), DDC services: \(serviceCount)")
    }
}

/// The window server reports a display change (plug, unplug, mode change, wake): the services are matched again in
/// the background once the change is done, and the next step rescans if that has not happened yet.
private func displayReconfigured(
    _: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let brightness = Unmanaged<ExternalBrightness>.fromOpaque(userInfo).takeUnretainedValue()
    brightness.configurationChanged.store(true, ordering: .relaxed)
    if !flags.contains(.beginConfigurationFlag) {
        brightness.scheduleScan()
    }
}

/// The external displays that the last registry scan found without an audio/video service, so DDC/CI cannot reach
/// them. A display the scan has not seen yet may have one. Safe from any thread; `mayHaveService` never allocates.
public final class DDCReachability: Sendable {
    private let withoutService = Mutex(Set<CGDirectDisplayID>())

    public init() {}

    /// Records a scan: of the `online` external displays, those not in `matched` have no service.
    public func update(online: [CGDirectDisplayID], matched: some Sequence<CGDirectDisplayID>) {
        var missing = Set(online)
        missing.subtract(matched)
        withoutService.withLock { $0 = missing }
    }

    public func mayHaveService(_ display: CGDirectDisplayID) -> Bool {
        withoutService.withLock { !$0.contains(display) }
    }
}
