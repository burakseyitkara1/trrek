import Testing
@testable import TrrekEngine

@Test func bufferRejectsSeventeenthTouch() {
    var buffer = TouchBuffer()
    for slot in 0 ..< TouchBuffer.capacity {
        let accepted = buffer.append(Touch(id: Int32(slot), x: 0.5, y: 0.5, majorAxisMM: 8))
        #expect(accepted)
    }
    #expect(buffer.count == 16)
    let overflow = buffer.append(Touch(id: 99, x: 0.1, y: 0.1, majorAxisMM: 8))
    #expect(overflow == false)
    #expect(buffer.count == 16)
    #expect(buffer.contains(id: 99) == false)
}

@Test func bufferLookupByID() {
    var buffer = TouchBuffer()
    buffer.append(Touch(id: 1, x: 0.1, y: 0.5, majorAxisMM: 8))
    buffer.append(Touch(id: 2, x: 0.2, y: 0.5, majorAxisMM: 8))
    buffer.append(Touch(id: 3, x: 0.3, y: 0.5, majorAxisMM: 8))
    #expect(buffer.touch(id: 2)?.x == 0.2)
    #expect(buffer.contains(id: 3))
    #expect(buffer.contains(id: 9) == false)
    #expect(buffer.touch(id: 9) == nil)
    #expect(buffer[0].id == 1)
}

@Test func bufferEqualityIgnoresUnusedSlots() {
    var lhs = TouchBuffer()
    var rhs = TouchBuffer()
    #expect(lhs == rhs)
    lhs.append(Touch(id: 1, x: 0.1, y: 0.1, majorAxisMM: 8))
    #expect(lhs != rhs)
    rhs.append(Touch(id: 1, x: 0.1, y: 0.1, majorAxisMM: 8))
    #expect(lhs == rhs)
}

@Test func frameBuilderConvertsMillimetres() {
    let frame = FrameBuilder().frame(t: 1, [(id: 5, xMM: 60, yMM: 20)])
    #expect(frame.touches.count == 1)
    #expect(frame.touches[0].x == 0.5)
    #expect(frame.touches[0].y == 0.25)
    #expect(frame.deviceID == 1)
}
