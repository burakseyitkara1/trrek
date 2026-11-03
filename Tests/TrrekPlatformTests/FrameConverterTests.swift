import CMultitouch
import Testing
import TrrekEngine
import TrrekPlatform

private let geometry = DeviceGeometry(widthMM: 121.94, heightMM: 74.08, isBuiltIn: true)

private func convert(_ contacts: [MTTouch], timestamp: Double = 1.5, deviceID: UInt64 = 7) -> Frame {
    contacts.withUnsafeBufferPointer {
        FrameConverter.frame(touches: $0, timestamp: timestamp, deviceID: deviceID, geometry: geometry)
    }
}

@Test func converterKeepsOnlyTouchingStates() {
    let frame = convert([
        contact(id: 1, state: 1),
        contact(id: 3, state: 3),
        contact(id: 4, state: 4),
        contact(id: 5, state: 5)
    ])
    #expect(frame.touches.count == 2)
    #expect(frame.touches[0].id == 3)
    #expect(frame.touches[1].id == 4)
    #expect(frame.touches.contains(id: 1) == false)
    #expect(frame.touches.contains(id: 5) == false)
}

@Test func converterMapsFields() {
    let frame = convert([contact(id: 42, state: 4, nx: 0.5, ny: 0.25, majorAxis: 8.5)], timestamp: 12.25, deviceID: 99)
    #expect(frame.touches.count == 1)
    #expect(frame.touches[0] == Touch(id: 42, x: 0.5, y: 0.25, majorAxisMM: 8.5))
    #expect(frame.timestamp == 12.25)
    #expect(frame.deviceID == 99)
    #expect(frame.geometry == geometry)
}

@Test func converterTruncatesAtSixteen() {
    let contacts = (0 ..< 20).map { contact(id: Int32($0), state: 4) }
    let frame = convert(contacts)
    #expect(frame.touches.count == 16)
    #expect(frame.touches[15].id == 15)
    #expect(frame.touches.contains(id: 16) == false)
}

@Test func converterHandlesEmptyFrame() {
    let empty = UnsafeBufferPointer<MTTouch>(start: nil, count: 0)
    let frame = FrameConverter.frame(touches: empty, timestamp: 3, deviceID: 1, geometry: geometry)
    #expect(frame.touches == TouchBuffer())
    #expect(frame.timestamp == 3)
}
