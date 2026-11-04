import CoreGraphics
import Foundation

/// An external display as the window server describes it: the identity from its EDID.
public struct DisplayDescriptor: Equatable, Sendable {
    public let id: CGDirectDisplayID
    /// The EDID manufacturer ID in its packed form (three 5-bit letters).
    public let vendor: UInt32
    public let model: UInt32
    /// 0 when the EDID carries no serial number.
    public let serial: UInt32

    public init(id: CGDirectDisplayID, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.id = id
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    /// The descriptor of an online display, read from the window server.
    public init(display: CGDirectDisplayID) {
        self.init(
            id: display,
            vendor: CGDisplayVendorNumber(display),
            model: CGDisplayModelNumber(display),
            serial: CGDisplaySerialNumber(display)
        )
    }
}

/// An external display's audio/video service in the I/O Registry, with the EDID identity of the display entry
/// nearest before it, when one was found.
public struct ServiceDescriptor: Equatable, Sendable {
    public let vendor: UInt32?
    public let model: UInt32?
    public let serial: UInt32?

    public init(vendor: UInt32?, model: UInt32?, serial: UInt32?) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }

    /// Reads the identity from a display entry's "DisplayAttributes" dictionary: its "ProductAttributes" hold the
    /// three-letter manufacturer ID, the product ID and the serial number. Missing values stay `nil`.
    public init(displayAttributes: [String: Any]?) {
        let product = displayAttributes?[DisplayRegistryKeys.productAttributes] as? [String: Any]
        let manufacturer = product?[DisplayRegistryKeys.manufacturerID] as? String
        self.init(
            vendor: manufacturer.flatMap(DisplayServiceMatcher.vendorNumber(manufacturerID:)),
            model: (product?[DisplayRegistryKeys.productID] as? NSNumber)?.uint32Value,
            serial: (product?[DisplayRegistryKeys.serialNumber] as? NSNumber)?.uint32Value
        )
    }
}

/// Pairs external displays with their audio/video services.
public enum DisplayServiceMatcher {
    /// Maps each display to the index of its service in `services`. A display takes the unused service whose
    /// vendor, model and serial number all match; then, for displays still unmatched, one whose vendor and model
    /// match and whose serial is missing on either side. Displays left over take the remaining services in order.
    /// No service is used twice; displays beyond the number of services stay unmapped.
    public static func match(displays: [DisplayDescriptor], services: [ServiceDescriptor]) -> [CGDirectDisplayID: Int] {
        var result: [CGDirectDisplayID: Int] = [:]
        var used = Set<Int>()

        func assign(_ isMatch: (DisplayDescriptor, ServiceDescriptor) -> Bool) {
            for display in displays where result[display.id] == nil {
                let index = services.indices.first { !used.contains($0) && isMatch(display, services[$0]) }
                if let index {
                    result[display.id] = index
                    used.insert(index)
                }
            }
        }

        assign { display, service in
            sameProduct(display, service) && display.serial != 0 && service.serial == display.serial
        }
        assign { display, service in
            sameProduct(display, service) && (display.serial == 0 || (service.serial ?? 0) == 0)
        }
        assign { _, _ in true }
        return result
    }

    /// The packed form of a three-letter EDID manufacturer ID ("DEL" → 0x10AC), as the window server reports
    /// vendor numbers: each letter A–Z becomes 1–26 in five bits, first letter highest.
    public static func vendorNumber(manufacturerID: String) -> UInt32? {
        let letters = Array(manufacturerID.uppercased().unicodeScalars)
        guard letters.count == 3 else { return nil }
        var value: UInt32 = 0
        for letter in letters {
            guard letter.value >= 0x41, letter.value <= 0x5A else { return nil }
            value = value << 5 | (letter.value - 0x40)
        }
        return value
    }

    private static func sameProduct(_ display: DisplayDescriptor, _ service: ServiceDescriptor) -> Bool {
        service.vendor == display.vendor && service.model == display.model
    }
}
