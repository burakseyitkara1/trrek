import Foundation
import ObjectiveC

/// Reads and steps the built-in keyboard backlight through the system brightness client.
///
/// The client class and selectors come from `PrivateSymbols.coreBrightness`; their implementations are
/// called directly as C function pointers. Creation fails (`nil`) when the class, a selector or a keyboard
/// backlight ID is missing, so a live instance is always available. Thread-safe: calls are serialized.
public final class KeyboardBacklight: KeyboardBacklightControlling, @unchecked Sendable {
    private typealias BrightnessGetter = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias BrightnessSetter = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    private static let coarseStep: Float = 1.0 / 16.0
    private static let fineStep: Float = 1.0 / 64.0

    private let client: NSObject
    private let keyboardID: UInt64
    private let getSelector: Selector
    private let setSelector: Selector
    private let getBrightness: BrightnessGetter
    private let setBrightness: BrightnessSetter
    private let lock = NSLock()

    public var isAvailable: Bool {
        true
    }

    public init?() {
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
        self.client = client
        keyboardID = first.uint64Value
        self.getSelector = getSelector
        self.setSelector = setSelector
        getBrightness = unsafeBitCast(client.method(for: getSelector), to: BrightnessGetter.self)
        setBrightness = unsafeBitCast(client.method(for: setSelector), to: BrightnessSetter.self)
    }

    /// The current backlight level in 0...1, or `nil` when it cannot be read.
    public func level() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        return currentLevel()
    }

    /// Moves the level by 1/16 (1/64 when `fine`) in the direction of `direction`, clamped to 0...1.
    /// Returns the new level, or `nil` when it could not be read or written.
    public func step(_ direction: Int, fine: Bool) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard let current = currentLevel() else { return nil }
        let delta = (fine ? Self.fineStep : Self.coarseStep) * Float(direction.signum())
        let target = min(max(current + delta, 0), 1)
        guard setBrightness(client, setSelector, target, 0, true, keyboardID) else {
            platformLogger.error("keyboard backlight write failed")
            return nil
        }
        return target
    }

    private func currentLevel() -> Float? {
        let value = getBrightness(client, getSelector, keyboardID)
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}
