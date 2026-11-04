import Dispatch
import Foundation
import ObjectiveC

/// Reads and steps the built-in keyboard backlight through the system brightness client.
///
/// The client class and selectors come from `PrivateSymbols.coreBrightness`; their implementations are
/// called directly as C function pointers. Creation fails (`nil`) when the class, a selector or a keyboard
/// backlight ID is missing, so a live instance is always available.
///
/// Reading the level from the client takes about a millisecond (`TrrekProbe backlight bench`), too long for the
/// frame thread on every step. The bridge therefore caches the level: `level()` and `step` answer from the cache
/// while it is fresh (see `BacklightLevelCache`), and the write runs on a serial queue, coalesced to the newest
/// target.
///
/// Thread-safe: the cache and the pending write are guarded by `lock`; writes run only on the queue. Every call
/// into the client (a read on the caller's thread, a write on the queue) also holds `clientLock`, so a read never
/// overlaps a write; a write takes about 0.02 ms, so a read waits at most that long. Lock order: `lock`, then
/// `clientLock`; a write never takes `lock` while it holds `clientLock`.
public final class KeyboardBacklight: KeyboardBacklightControlling, @unchecked Sendable {
    private typealias BrightnessGetter = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias BrightnessSetter = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    /// Reads the raw level from the client.
    private let readClient: () -> Float
    /// Writes a level to the client; `false` when it failed.
    private let writeClient: (Float) -> Bool
    private let writeQueue: DispatchQueue
    private let lock = NSLock()
    /// Serializes the client calls.
    private let clientLock = NSLock()

    /// Guarded by `lock`.
    private var cache = BacklightLevelCache()
    /// The newest target not yet written; a queued block takes it.
    private var pendingWrite: Float?

    public var isAvailable: Bool {
        true
    }

    public convenience init?() {
        guard let symbols = PrivateSymbols.coreBrightness,
              let clientClass = NSClassFromString(symbols.clientClassName) as? NSObject.Type
        else {
            platformLogger.error("keyboard backlight client unavailable")
            return nil
        }
        let client = clientClass.init()
        let copySelector = NSSelectorFromString(symbols.copyKeyboardIDsSelector)
        let getSelector = NSSelectorFromString(symbols.brightnessSelector)
        let setSelector = NSSelectorFromString(symbols.setBrightnessSelector)
        guard client.responds(to: copySelector), client.responds(to: getSelector),
              client.responds(to: setSelector)
        else {
            platformLogger.error("keyboard backlight selectors missing")
            return nil
        }
        // The selector follows the copy naming rule, so the returned array is owned by the caller.
        guard let ids = client.perform(copySelector)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first
        else {
            platformLogger.error("no keyboard backlight found")
            return nil
        }
        let keyboardID = first.uint64Value
        let getBrightness = unsafeBitCast(client.method(for: getSelector), to: BrightnessGetter.self)
        let setBrightness = unsafeBitCast(client.method(for: setSelector), to: BrightnessSetter.self)
        self.init(
            read: { getBrightness(client, getSelector, keyboardID) },
            write: { setBrightness(client, setSelector, $0, 0, true, keyboardID) }
        )
    }

    /// A bridge over `read` and `write` (tests pass a fake client). `queue` runs the writes and must be serial.
    init(
        read: @escaping () -> Float,
        write: @escaping (Float) -> Bool,
        queue: DispatchQueue = DispatchQueue(label: "com.burakseyitkara.trrek.backlight", qos: .userInitiated)
    ) {
        readClient = read
        writeClient = write
        writeQueue = queue
    }

    /// The current backlight level in 0...1, or `nil` when it cannot be read. Answers from the cache while it is
    /// fresh, otherwise reads the client.
    public func level() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return cachedOrReadLevel(at: Self.now())
    }

    /// Moves the level by 1/16 (1/64 when `fine`) in the direction of `direction`, clamped to 0...1, and returns the
    /// new level, or `nil` when the current level could not be read. The write itself runs on the serial queue; a
    /// failed write is logged and drops the cache, so the next step reads the client again.
    public func step(_ direction: Int, fine: Bool) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        let now = Self.now()
        guard let current = cachedOrReadLevel(at: now) else { return nil }
        let target = BacklightLevelCache.target(from: current, direction: direction, fine: fine)
        cache.store(target, at: now)
        let schedule = pendingWrite == nil
        pendingWrite = target
        if schedule {
            writeQueue.async { [self] in
                writePending()
            }
        }
        return target
    }

    /// Reads the level from the client, bypassing the cache (for measurements).
    public func readLevelUncached() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return readLevel()
    }

    /// Writes `level`, clamped to 0...1, after any queued write, and waits for it. Returns `false` when the write
    /// failed.
    @discardableResult
    public func setLevel(_ level: Float) -> Bool {
        let target = min(max(level, 0), 1)
        return writeQueue.sync {
            lock.lock()
            pendingWrite = nil
            cache.store(target, at: Self.now())
            lock.unlock()
            return write(target)
        }
    }

    // MARK: - Private

    /// Runs on `writeQueue`.
    private func writePending() {
        lock.lock()
        let target = pendingWrite
        pendingWrite = nil
        lock.unlock()
        guard let target else { return }
        write(target)
    }

    /// Runs on `writeQueue`, without `lock`.
    @discardableResult
    private func write(_ target: Float) -> Bool {
        clientLock.lock()
        let written = writeClient(target)
        clientLock.unlock()
        guard written else {
            platformLogger.error("keyboard backlight write failed")
            lock.lock()
            cache.invalidate()
            lock.unlock()
            return false
        }
        return true
    }

    /// Call with `lock` held.
    private func cachedOrReadLevel(at now: TimeInterval) -> Float? {
        if let cached = cache.level(at: now) {
            return cached
        }
        guard let value = readLevel() else { return nil }
        cache.store(value, at: now)
        return value
    }

    private func readLevel() -> Float? {
        clientLock.lock()
        let value = readClient()
        clientLock.unlock()
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    private static func now() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}

/// The keyboard backlight level trrek last read or set, and the step arithmetic. Pure.
///
/// The level is trusted for `lifetime` after it was stored. A slide steps several times a second, so it reads the
/// client once at its start and then works from the cache; after a pause the level is read again, picking up
/// changes made with the keyboard's own keys or by the system's automatic adjustment.
struct BacklightLevelCache {
    static let lifetime: TimeInterval = 1.5
    static let coarseStep: Float = 1.0 / 16.0
    static let fineStep: Float = 1.0 / 64.0

    private var level: Float?
    private var storedAt: TimeInterval = 0

    /// The cached level, or `nil` when there is none or it is older than `lifetime` at `now`.
    func level(at now: TimeInterval) -> Float? {
        guard let level, now >= storedAt, now - storedAt < Self.lifetime else { return nil }
        return level
    }

    mutating func store(_ level: Float, at now: TimeInterval) {
        self.level = level
        storedAt = now
    }

    mutating func invalidate() {
        level = nil
    }

    /// `current` moved by one step (1/16, or 1/64 when `fine`) in the direction of `direction`, clamped to 0...1.
    static func target(from current: Float, direction: Int, fine: Bool) -> Float {
        let delta = (fine ? fineStep : coarseStep) * Float(direction.signum())
        return min(max(current + delta, 0), 1)
    }
}
