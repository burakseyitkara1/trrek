import CoreGraphics
import Foundation
import IOKit

/// A retained audio/video service of an external display and the DDC/CI exchanges over its I2C bus.
///
/// Every exchange waits on the bus with `usleep`; callers run it on a background queue.
final class DDCService {
    /// DDC/CI asks the host to wait at least 40 ms after a request before reading the reply.
    static let replyDelay: useconds_t = 40000
    /// DDC/CI asks the host to wait at least 50 ms after a Set VCP Feature before the next message.
    static let writeDelay: useconds_t = 50000
    /// Reads are retried this many times; displays often miss the first request.
    static let readAttempts = 3

    let ref: CFTypeRef
    private let symbols: AVServiceSymbols

    init(_ ref: CFTypeRef, symbols: AVServiceSymbols) {
        self.ref = ref
        self.symbols = symbols
    }

    /// Reads the brightness, trying up to `readAttempts` times with a pause between attempts.
    func read() -> Result<(current: UInt16, maximum: UInt16), DDCError> {
        var failure = DDCError.invalidReply
        for attempt in 0 ..< Self.readAttempts {
            if attempt > 0 {
                usleep(Self.replyDelay)
            }
            let exchange = exchange(readOffset: DDCPacket.sourceAddress)
            if let value = exchange.value {
                return .success(value)
            }
            failure = exchange.error
        }
        return .failure(failure)
    }

    /// Sends a Get VCP Feature request for brightness, waits, and reads the reply at `readOffset`.
    func exchange(readOffset: UInt8) -> DDCReadAttempt {
        let writeResult = send(DDCPacket.getVCPRequest(DDCPacket.brightnessCode))
        guard writeResult == kIOReturnSuccess else {
            return DDCReadAttempt(
                readOffset: readOffset, writeResult: writeResult, readResult: nil, reply: [], value: nil
            )
        }
        usleep(Self.replyDelay)
        var reply = [UInt8](repeating: 0, count: DDCPacket.getVCPReplyLength)
        let readResult = reply.withUnsafeMutableBytes { buffer in
            symbols.readI2C(
                ref,
                UInt32(DDCPacket.chipAddress),
                UInt32(readOffset),
                buffer.baseAddress!,
                UInt32(buffer.count)
            )
        }
        let value = readResult == kIOReturnSuccess ? DDCPacket.parseGetVCPReply(reply) : nil
        return DDCReadAttempt(
            readOffset: readOffset, writeResult: writeResult, readResult: readResult, reply: reply, value: value
        )
    }

    /// Sends a host message. Its first byte, the source address, goes as the transfer's data address.
    func send(_ message: [UInt8]) -> IOReturn {
        guard let dataAddress = message.first else { return kIOReturnBadArgument }
        var payload = Array(message.dropFirst())
        return payload.withUnsafeMutableBytes { buffer in
            symbols.writeI2C(
                ref,
                UInt32(DDCPacket.chipAddress),
                UInt32(dataAddress),
                buffer.baseAddress!,
                UInt32(buffer.count)
            )
        }
    }
}

/// One Get VCP Feature exchange for brightness, for diagnostics.
public struct DDCReadAttempt: Sendable {
    /// The offset passed to the I2C read.
    public let readOffset: UInt8
    public let writeResult: IOReturn
    /// `nil` when the request could not be written, so nothing was read.
    public let readResult: IOReturn?
    /// The raw reply bytes; empty when nothing was read.
    public let reply: [UInt8]
    public let value: (current: UInt16, maximum: UInt16)?

    var error: DDCError {
        if writeResult != kIOReturnSuccess {
            return .writeFailed(writeResult)
        }
        if let readResult, readResult != kIOReturnSuccess {
            return .readFailed(readResult)
        }
        return .invalidReply
    }
}

/// Finds external displays and their audio/video services.
enum DisplayRegistry {
    /// The online displays that are not built in, in the window server's order.
    static func onlineExternalDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }

    /// The external audio/video services in I/O Registry order. Each takes the identity of the nearest display
    /// entry ("DisplayAttributes") before it in the walk, which is the display it belongs to when the registry
    /// lists a display's entries together. Every service entry, external or not, uses up the identity before it,
    /// so a display's identity never carries over to a later service; a mismatch falls back to order in the matcher.
    static func externalServices(
        symbols: AVServiceSymbols
    ) -> [(descriptor: ServiceDescriptor, service: DDCService)] {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(
            kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [(descriptor: ServiceDescriptor, service: DDCService)] = []
        var attributes: [String: Any]?
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            if let value = property(entry, DisplayRegistryKeys.displayAttributes) as? [String: Any] {
                attributes = value
                continue
            }
            guard IOObjectConformsTo(entry, DisplayRegistryKeys.avServiceClass) != 0 else { continue }
            let identity = attributes
            attributes = nil
            guard property(entry, DisplayRegistryKeys.location) as? String == DisplayRegistryKeys.external,
                  let created = symbols.createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
            else { continue }
            found.append((ServiceDescriptor(displayAttributes: identity), DDCService(created, symbols: symbols)))
        }
        return found
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
