import CoreGraphics
import Foundation

/// The modifier that must be held (or toggled) for slides to run.
public enum HoldKey: String, CaseIterable, Codable, Sendable {
    case none, shift, control, option, command

    /// The event flag of the modifier, or `nil` for `.none`.
    public var flag: CGEventFlags? {
        switch self {
        case .none: nil
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        }
    }
}

/// How the hold key gates slides.
public enum HoldKeyMode: String, CaseIterable, Codable, Sendable {
    /// Slides run while the modifier is held down.
    case hold
    /// A lone, quick press and release of the modifier switches slides on or off.
    case toggle
}

/// Turns modifier and key events into the "hold key satisfied" state. Pure value logic: the caller feeds it
/// events from the input monitor and forwards changes to the engine.
public struct HoldKeyTracker: Sendable {
    /// Longest press, from modifier down to modifier up, that still counts as a toggle tap.
    static let toggleWindow: TimeInterval = 0.3

    private static let modifierFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    public let key: HoldKey
    public let mode: HoldKeyMode
    public private(set) var isSatisfied: Bool

    private var isDown = false
    private var pressedAt: TimeInterval = 0
    private var isLonePress = false

    public init(key: HoldKey, mode: HoldKeyMode) {
        self.key = key
        self.mode = mode
        isSatisfied = key == .none
    }

    /// Feeds the full flags of a `flagsChanged` event. Returns whether `isSatisfied` changed.
    public mutating func handleFlagsChanged(_ flags: CGEventFlags, at time: TimeInterval) -> Bool {
        guard let flag = key.flag else { return false }
        let down = flags.contains(flag)
        let wasDown = isDown
        isDown = down
        switch mode {
        case .hold:
            return update(down)
        case .toggle:
            if down {
                // A lone press starts with no other modifier held, and stops being one when another joins.
                let othersHeld = !flags.intersection(Self.modifierFlags).subtracting(flag).isEmpty
                if !wasDown {
                    pressedAt = time
                    isLonePress = !othersHeld
                } else if othersHeld {
                    isLonePress = false
                }
                return false
            }
            guard wasDown else { return false }
            let isTap = isLonePress && time - pressedAt <= Self.toggleWindow
            isLonePress = false
            guard isTap else { return false }
            isSatisfied.toggle()
            return true
        }
    }

    /// Notes a non-modifier key press; a modifier held during one is a chord, not a toggle tap.
    public mutating func handleKeyDown(at _: TimeInterval) {
        isLonePress = false
    }

    /// Notes a mouse button press; a modifier held during one is a modifier-click, not a toggle tap.
    public mutating func handleMouseDown(at time: TimeInterval) {
        handleKeyDown(at: time)
    }

    /// Returns to the initial state: satisfied only for `.none`, with no press in flight.
    public mutating func reset() {
        isSatisfied = key == .none
        cancelPress()
    }

    /// Forgets the press in flight, keeping `isSatisfied`; for when a key-up may have been missed.
    public mutating func cancelPress() {
        isDown = false
        pressedAt = 0
        isLonePress = false
    }

    private mutating func update(_ value: Bool) -> Bool {
        guard isSatisfied != value else { return false }
        isSatisfied = value
        return true
    }
}
