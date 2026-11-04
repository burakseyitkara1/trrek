import Testing
import TrrekPlatform

/// A Get VCP Feature reply for brightness as a display sends it: source 0x6E, length 0x88, opcode 0x02, result 0,
/// code 0x10, type 0, maximum 100, current 50, checksum seeded with 0x50.
private func reply(current: UInt16 = 50, maximum: UInt16 = 100, result: UInt8 = 0) -> [UInt8] {
    var bytes: [UInt8] = [
        0x6E, 0x88, 0x02, result, 0x10, 0x00,
        UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)
    ]
    bytes.append(bytes.reduce(0x50, ^))
    return bytes
}

@Test func setVCPPacketMatchesStandard() {
    // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
    #expect(DDCPacket.setVCP(0x10, value: 50) == [0x51, 0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    // The high byte goes first: 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x01 ^ 0x2C = 0x85
    #expect(DDCPacket.setVCP(0x10, value: 300) == [0x51, 0x84, 0x03, 0x10, 0x01, 0x2C, 0x85])
    // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
    #expect(DDCPacket.getVCPRequest(0x10) == [0x51, 0x82, 0x01, 0x10, 0xAC])
    // Every host message XORs to zero with the destination address in front.
    for packet in [DDCPacket.setVCP(0x10, value: 77), DDCPacket.getVCPRequest(0x12)] {
        #expect(packet.reduce(0x6E, ^) == 0)
    }
}

@Test func parsesGetVCPReply() {
    let value = DDCPacket.parseGetVCPReply(reply())
    #expect(value?.current == 50)
    #expect(value?.maximum == 100)
    let wide = DDCPacket.parseGetVCPReply(reply(current: 0x0123, maximum: 0x0400))
    #expect(wide?.current == 0x0123)
    #expect(wide?.maximum == 0x0400)
    // Trailing bytes after the reply are ignored.
    #expect(DDCPacket.parseGetVCPReply(reply() + [0x00, 0x00])?.current == 50)
}

@Test func rejectsCorruptReply() {
    var badChecksum = reply()
    badChecksum[10] ^= 0x01
    #expect(DDCPacket.parseGetVCPReply(badChecksum) == nil)

    var flippedValue = reply()
    flippedValue[9] ^= 0x04
    #expect(DDCPacket.parseGetVCPReply(flippedValue) == nil)

    // Unsupported control: a non-zero result code, even with a valid checksum.
    #expect(DDCPacket.parseGetVCPReply(reply(result: 0x01)) == nil)
    // Too short, wrong source, wrong opcode, another VCP code.
    #expect(DDCPacket.parseGetVCPReply(Array(reply().prefix(10))) == nil)
    #expect(DDCPacket.parseGetVCPReply([]) == nil)
    var wrongSource = reply()
    wrongSource[0] = 0x6F
    wrongSource[10] = Array(wrongSource.prefix(10)).reduce(0x50, ^)
    #expect(DDCPacket.parseGetVCPReply(wrongSource) == nil)
    var wrongOpcode = reply()
    wrongOpcode[2] = 0x03
    wrongOpcode[10] = Array(wrongOpcode.prefix(10)).reduce(0x50, ^)
    #expect(DDCPacket.parseGetVCPReply(wrongOpcode) == nil)
    #expect(DDCPacket.parseGetVCPReply(reply(), code: 0x12) == nil)
    // All zeros, as an idle bus reads.
    #expect(DDCPacket.parseGetVCPReply([UInt8](repeating: 0, count: 11)) == nil)
}
