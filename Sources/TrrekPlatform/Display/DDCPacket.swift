/// Builds and parses DDC/CI messages, as the VESA DDC/CI standard lays them out on the I2C bus.
///
/// A message from the host to the display travels to I2C address 0x6E (the display's 7-bit address 0x37 with
/// the write bit) and reads:
///
///     source 0x51 | 0x80 | length | opcode, data… | checksum
///
/// `length` counts the opcode and data bytes; its top bit marks a DDC/CI message. The checksum is the XOR of
/// every byte of the message, starting with the destination address 0x6E, which is on the bus but not in the
/// returned bytes. The display's reply is read from address 0x6F and has the same shape, with the display's
/// address 0x6E as the source; its checksum starts from the host's virtual address 0x50 instead.
///
/// The bytes returned here begin with the source byte 0x51. The I2C call that sends them takes that first byte as
/// its separate data address argument and the rest as the buffer.
public enum DDCPacket {
    /// The display's I2C address in 8-bit (write) form; the first byte of every host checksum.
    public static let destinationAddress: UInt8 = 0x6E
    /// The host's source address, the first byte of every host message.
    public static let sourceAddress: UInt8 = 0x51
    /// The address a reply's checksum starts from, standing in for the host as the destination.
    public static let replyChecksumSeed: UInt8 = 0x50
    /// The display's 7-bit I2C address.
    public static let chipAddress: UInt8 = 0x37
    /// The VCP code of the display's luminance control.
    public static let brightnessCode: UInt8 = 0x10

    enum Opcode {
        static let getVCP: UInt8 = 0x01
        static let getVCPReply: UInt8 = 0x02
        static let setVCP: UInt8 = 0x03
    }

    /// The length of a Get VCP Feature reply: source, length, opcode, result, code, type, maximum (2), current (2)
    /// and the checksum.
    public static let getVCPReplyLength = 11

    /// A Set VCP Feature message that sets `code` to `value` (high byte first).
    public static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        message([Opcode.setVCP, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// A Get VCP Feature request for `code`.
    public static func getVCPRequest(_ code: UInt8) -> [UInt8] {
        message([Opcode.getVCP, code])
    }

    /// The current and maximum value from a Get VCP Feature reply for `code`, or `nil` when the reply is not one:
    /// wrong source, length or opcode, a non-zero result code (the display does not support `code`), another VCP
    /// code, or a bad checksum.
    public static func parseGetVCPReply(
        _ bytes: [UInt8],
        code: UInt8 = brightnessCode
    ) -> (current: UInt16, maximum: UInt16)? {
        guard bytes.count >= getVCPReplyLength else { return nil }
        let reply = bytes.prefix(getVCPReplyLength)
        let payloadLength = getVCPReplyLength - 3
        guard reply[0] == destinationAddress,
              reply[1] == 0x80 | UInt8(payloadLength),
              reply[2] == Opcode.getVCPReply,
              reply[3] == 0x00,
              reply[4] == code
        else { return nil }
        let checksum = reply.dropLast().reduce(replyChecksumSeed, ^)
        guard checksum == reply[getVCPReplyLength - 1] else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }

    /// The XOR checksum of a host message's bytes, seeded with the destination address.
    public static func checksum(_ bytes: some Sequence<UInt8>) -> UInt8 {
        bytes.reduce(destinationAddress, ^)
    }

    private static func message(_ payload: [UInt8]) -> [UInt8] {
        var bytes = [sourceAddress, 0x80 | UInt8(payload.count)] + payload
        bytes.append(checksum(bytes))
        return bytes
    }
}
