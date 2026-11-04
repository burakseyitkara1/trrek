import CoreGraphics
import TrrekEngine
import TrrekPlatform

// Test doubles for the dispatcher's ports. Each records its calls in order. Tests drive them from a
// single thread, so the recorded arrays need no locking.

final class FakeMediaKeys: MediaKeyPosting, @unchecked Sendable {
    struct Call: Equatable {
        let key: MediaKey
        let fine: Bool
    }

    private(set) var calls: [Call] = []

    func post(_ key: MediaKey, fine: Bool) {
        calls.append(Call(key: key, fine: fine))
    }
}

final class FakeKeys: KeyPosting, @unchecked Sendable {
    enum Call: Equatable {
        case press(CGKeyCode, CGEventFlags)
        case modifierDown(CGKeyCode, CGEventFlags)
        case modifierUp(CGKeyCode)
    }

    private(set) var calls: [Call] = []

    func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        calls.append(.press(keyCode, flags))
    }

    func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        calls.append(.modifierDown(keyCode, flags))
    }

    func modifierUp(_ keyCode: CGKeyCode) {
        calls.append(.modifierUp(keyCode))
    }

    func count(_ call: Call) -> Int {
        calls.filter { $0 == call }.count
    }

    func removeAll() {
        calls.removeAll()
    }
}

final class FakeMouse: MousePosting, @unchecked Sendable {
    private(set) var middleClicks = 0

    func middleClick() {
        middleClicks += 1
    }
}

final class FakeHaptics: HapticPerforming, @unchecked Sendable {
    struct Call: Equatable {
        let event: HapticEvent
        let strength: HapticStrength
    }

    private(set) var calls: [Call] = []

    func perform(_ event: HapticEvent, strength: HapticStrength) {
        calls.append(Call(event: event, strength: strength))
    }
}

final class FakeFreezer: CursorFreezing, @unchecked Sendable {
    private(set) var calls: [Bool] = []

    var last: Bool? {
        calls.last
    }

    func setFreeze(_ on: Bool) {
        calls.append(on)
    }
}

/// A backlight that moves by 1/16 per step (1/64 when fine) and clamps to 0...1.
final class FakeBacklight: KeyboardBacklightControlling, @unchecked Sendable {
    private(set) var current: Float
    private(set) var steps: [(direction: Int, fine: Bool)] = []
    let isAvailable = true

    init(level: Float) {
        current = level
    }

    func level() -> Float? {
        current
    }

    func step(_ direction: Int, fine: Bool) -> Float? {
        steps.append((direction, fine))
        let delta: Float = fine ? 1 / 64 : 1 / 16
        current = min(1, max(0, current + Float(direction) * delta))
        return current
    }
}

final class FakeOverlay: LevelOverlayPresenting, @unchecked Sendable {
    struct Call: Equatable {
        let kind: OverlayKind
        let level: Float
        let label: String?
    }

    private(set) var calls: [Call] = []

    func show(kind: OverlayKind, level: Float, label: String?) {
        calls.append(Call(kind: kind, level: level, label: label))
    }
}
