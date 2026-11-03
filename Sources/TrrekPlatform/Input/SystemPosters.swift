import CoreGraphics

/// Media keys posted to the system.
public struct SystemMediaKeys: MediaKeyPosting {
    public init() {}

    public func post(_ key: MediaKey, fine: Bool) {
        MediaKeyPoster.post(key, fine: fine)
    }
}

/// Keyboard events posted to the system.
public struct SystemKeys: KeyPosting {
    public init() {}

    public func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        KeyPoster.press(keyCode: keyCode, flags: flags)
    }

    public func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        KeyPoster.modifierDown(keyCode, flags: flags)
    }

    public func modifierUp(_ keyCode: CGKeyCode) {
        KeyPoster.modifierUp(keyCode)
    }
}

/// Mouse events posted to the system.
public struct SystemMouse: MousePosting {
    public init() {}

    public func middleClick() {
        MousePoster.middleClick()
    }
}
