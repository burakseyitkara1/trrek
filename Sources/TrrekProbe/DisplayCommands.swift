import CoreGraphics
import Foundation
import TrrekPlatform

// MARK: - ddc

func runDDC(_ options: [String]) {
    guard options.first == "list" else {
        usageError("ddc needs: list")
    }
    output("display service symbols: \(PrivateSymbols.avService == nil ? "MISSING" : "ok")")
    if let pointer = DisplayLocator.displayUnderPointer() {
        let kind = CGDisplayIsBuiltin(pointer) != 0 ? "built-in" : "external"
        output("display under the pointer: \(pointer) (\(kind))")
    } else {
        output("display under the pointer: unknown")
    }
    guard let brightness = ExternalBrightness() else {
        output("external brightness unavailable")
        exit(1)
    }
    let (pairings, serviceCount) = brightness.pairings()
    output("external displays: \(pairings.count), DDC services: \(serviceCount)")
    for pairing in pairings {
        let display = pairing.display
        output(String(
            format: "display %u vendor=0x%04x model=0x%04x serial=%u",
            display.id, display.vendor, display.model, display.serial
        ))
        guard let index = pairing.serviceIndex, let service = pairing.service else {
            output("  service: none")
            continue
        }
        output("  service #\(index): \(identity(service))")
        switch brightness.diagnoseRead(display: display.id) {
        case let .success(attempts):
            for (number, attempt) in attempts.enumerated() {
                output("  attempt \(number + 1): \(describe(attempt))")
            }
            if let value = attempts.last?.value {
                output("  brightness: \(value.current)/\(value.maximum)")
            } else {
                output("  brightness: no valid reply")
            }
        case let .failure(error):
            output("  brightness: \(error)")
        }
    }
}

/// One exchange: the read offset, the write and read results and the raw reply bytes.
private func describe(_ attempt: DDCReadAttempt) -> String {
    var text = String(format: "offset=0x%02x write=0x%08x", attempt.readOffset, attempt.writeResult)
    if let readResult = attempt.readResult {
        text += String(format: " read=0x%08x", readResult)
        text += " reply=" + attempt.reply.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
    if let value = attempt.value {
        text += " -> \(value.current)/\(value.maximum)"
    }
    return text
}

private func identity(_ service: ServiceDescriptor) -> String {
    guard let vendor = service.vendor, let model = service.model else { return "no EDID identity (matched by order)" }
    return String(format: "vendor=0x%04x model=0x%04x serial=%u", vendor, model, service.serial ?? 0)
}
