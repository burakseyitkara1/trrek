import Foundation

/// One finger on the trackpad. `x` and `y` are normalized to 0...1 with the origin at the bottom-left.
public struct Touch: Sendable, Equatable, Hashable {
    public var id: Int32
    public var x: Float
    public var y: Float
    public var majorAxisMM: Float

    public init(id: Int32, x: Float, y: Float, majorAxisMM: Float) {
        self.id = id
        self.x = x
        self.y = y
        self.majorAxisMM = majorAxisMM
    }
}

/// Fixed-capacity touch storage; never allocates on the heap.
public struct TouchBuffer: Sendable, Equatable {
    public static let capacity = 16

    private var storage = InlineArray<16, Touch>(repeating: Touch(id: -1, x: 0, y: 0, majorAxisMM: 0))
    public private(set) var count = 0

    public init() {}

    /// Appends a touch; returns `false` and ignores it when the buffer is full.
    @discardableResult
    public mutating func append(_ touch: Touch) -> Bool {
        guard count < Self.capacity else { return false }
        storage[count] = touch
        count += 1
        return true
    }

    public subscript(_ index: Int) -> Touch {
        precondition(index >= 0 && index < count, "TouchBuffer index out of range")
        return storage[index]
    }

    public func contains(id: Int32) -> Bool {
        for index in 0 ..< count where storage[index].id == id {
            return true
        }
        return false
    }

    public func touch(id: Int32) -> Touch? {
        for index in 0 ..< count where storage[index].id == id {
            return storage[index]
        }
        return nil
    }

    public static func == (lhs: TouchBuffer, rhs: TouchBuffer) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in 0 ..< lhs.count where lhs.storage[index] != rhs.storage[index] {
            return false
        }
        return true
    }
}

public struct DeviceGeometry: Sendable, Equatable, Hashable {
    public var widthMM: Float
    public var heightMM: Float
    public var isBuiltIn: Bool

    public var isValid: Bool {
        widthMM > 0 && heightMM > 0
    }

    public init(widthMM: Float, heightMM: Float, isBuiltIn: Bool) {
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.isBuiltIn = isBuiltIn
    }
}

public struct Frame: Sendable, Equatable {
    public var deviceID: UInt64
    public var timestamp: TimeInterval
    public var geometry: DeviceGeometry
    public var touches: TouchBuffer

    public init(deviceID: UInt64, timestamp: TimeInterval, geometry: DeviceGeometry, touches: TouchBuffer) {
        self.deviceID = deviceID
        self.timestamp = timestamp
        self.geometry = geometry
        self.touches = touches
    }
}

public enum Edge: Sendable, Equatable, Hashable, CaseIterable {
    case left, right, top, bottom
}

public enum Corner: Sendable, Equatable, Hashable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public enum Zone: Sendable, Equatable, Hashable {
    case edge(Edge)
    case corner(Corner)
    case none
}
