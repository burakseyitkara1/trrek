import CoreGraphics
import Foundation
import Testing
import TrrekPlatform

/// A display entry's "DisplayAttributes" as the registry lists it.
private func attributes(_ manufacturer: String, product: Int, serial: Int) -> [String: Any] {
    [
        "ProductAttributes": [
            "ManufacturerID": manufacturer,
            "ProductID": NSNumber(value: product),
            "SerialNumber": NSNumber(value: serial)
        ] as [String: Any]
    ]
}

@Test func matchesDisplaysByEDID() {
    #expect(DisplayServiceMatcher.vendorNumber(manufacturerID: "ABC") == 0x0443)
    #expect(DisplayServiceMatcher.vendorNumber(manufacturerID: "XYZ") == 0x633A)
    #expect(DisplayServiceMatcher.vendorNumber(manufacturerID: "A1C") == nil)

    // Two identical models told apart by serial, listed in the opposite order to the displays, plus a third.
    let services = [
        ServiceDescriptor(displayAttributes: attributes("ABC", product: 0xA0F1, serial: 222)),
        ServiceDescriptor(displayAttributes: attributes("XYZ", product: 0x5B7F, serial: 0)),
        ServiceDescriptor(displayAttributes: attributes("ABC", product: 0xA0F1, serial: 111))
    ]
    #expect(services[0] == ServiceDescriptor(vendor: 0x0443, model: 0xA0F1, serial: 222))

    let displays = [
        DisplayDescriptor(id: 7, vendor: 0x0443, model: 0xA0F1, serial: 111),
        DisplayDescriptor(id: 8, vendor: 0x633A, model: 0x5B7F, serial: 0),
        DisplayDescriptor(id: 9, vendor: 0x0443, model: 0xA0F1, serial: 222)
    ]
    let matched = DisplayServiceMatcher.match(displays: displays, services: services)
    #expect(matched == [7: 2, 8: 1, 9: 0])
}

@Test func fallsBackToOrder() {
    // Services without an identity go to the displays in order.
    let anonymous = [
        ServiceDescriptor(displayAttributes: nil),
        ServiceDescriptor(displayAttributes: [:])
    ]
    #expect(anonymous[0] == ServiceDescriptor(vendor: nil, model: nil, serial: nil))
    let displays = [
        DisplayDescriptor(id: 3, vendor: 0x0443, model: 1, serial: 5),
        DisplayDescriptor(id: 4, vendor: 0x633A, model: 2, serial: 6)
    ]
    #expect(DisplayServiceMatcher.match(displays: displays, services: anonymous) == [3: 0, 4: 1])

    // A display matched by identity keeps its service; the other takes what is left.
    let mixed = [
        ServiceDescriptor(vendor: nil, model: nil, serial: nil),
        ServiceDescriptor(vendor: 0x633A, model: 2, serial: 6)
    ]
    #expect(DisplayServiceMatcher.match(displays: displays, services: mixed) == [3: 0, 4: 1])
    let swapped = [mixed[1], mixed[0]]
    #expect(DisplayServiceMatcher.match(displays: displays, services: swapped) == [3: 1, 4: 0])

    // More displays than services: the extra display stays unmatched.
    #expect(DisplayServiceMatcher.match(displays: displays, services: [anonymous[0]]) == [3: 0])
    #expect(DisplayServiceMatcher.match(displays: displays, services: []).isEmpty)
}
