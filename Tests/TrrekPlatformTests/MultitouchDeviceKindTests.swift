import Foundation
import Testing
@testable import TrrekPlatform

// Property dictionaries shaped like the multitouch registry entries' HID properties. The values are what
// `IORegistryEntryCreateCFProperty` returns: strings, and arrays of dictionaries holding numbers.

private var builtInTrackpad: [String: Any] {
    [
        "HIDPointerAccelerationType": "HIDTrackpadAcceleration",
        "DeviceUsagePairs": [
            ["DeviceUsagePage": 1, "DeviceUsage": 2],
            ["DeviceUsagePage": 1, "DeviceUsage": 1],
            ["DeviceUsagePage": 13, "DeviceUsage": 5],
            ["DeviceUsagePage": 65280, "DeviceUsage": 12]
        ],
        "Family ID": 110,
        "MT Built-In": true
    ]
}

private var externalTrackpad: [String: Any] {
    [
        "HIDPointerAccelerationType": "HIDTrackpadAcceleration",
        "DeviceUsagePairs": [
            ["DeviceUsagePage": 1, "DeviceUsage": 2],
            ["DeviceUsagePage": 13, "DeviceUsage": 5]
        ],
        "MT Built-In": false
    ]
}

private var mouseWithTouchSurface: [String: Any] {
    [
        "HIDPointerAccelerationType": "HIDMouseAcceleration",
        "DeviceUsagePairs": [
            ["DeviceUsagePage": 1, "DeviceUsage": 2],
            ["DeviceUsagePage": 1, "DeviceUsage": 1],
            ["DeviceUsagePage": 65280, "DeviceUsage": 11]
        ],
        "MT Built-In": false
    ]
}

@Test func builtInTrackpadIsATrackpad() {
    #expect(MultitouchDeviceKind.classify(builtInTrackpad) == .trackpad)
}

@Test func externalTrackpadIsATrackpad() {
    #expect(MultitouchDeviceKind.classify(externalTrackpad) == .trackpad)
}

@Test func mouseWithTouchSurfaceIsNotATrackpad() {
    #expect(MultitouchDeviceKind.classify(mouseWithTouchSurface) == .other)
}

@Test func eitherSignalAloneMakesATrackpad() {
    #expect(MultitouchDeviceKind.classify(["HIDPointerAccelerationType": "HIDTrackpadAcceleration"]) == .trackpad)
    #expect(MultitouchDeviceKind.classify([
        "DeviceUsagePairs": [["DeviceUsagePage": 13, "DeviceUsage": 5]]
    ]) == .trackpad)
    // A trackpad usage wins over a pointer type that is not the trackpad one.
    #expect(MultitouchDeviceKind.classify([
        "HIDPointerAccelerationType": "HIDMouseAcceleration",
        "DeviceUsagePairs": [["DeviceUsagePage": 13, "DeviceUsage": 5]]
    ]) == .trackpad)
}

@Test func onlyANegativeSignalIsNotATrackpad() {
    #expect(MultitouchDeviceKind.classify(["HIDPointerAccelerationType": "HIDMouseAcceleration"]) == .other)
    #expect(MultitouchDeviceKind.classify([
        "DeviceUsagePairs": [["DeviceUsagePage": 1, "DeviceUsage": 2]]
    ]) == .other)
}

@Test func missingPropertiesFailOpen() {
    #expect(MultitouchDeviceKind.classify([:]) == .unknown)
    #expect(MultitouchDeviceKind.classify(["Family ID": 112, "MT Built-In": false]) == .unknown)
    // Properties of an unexpected type say nothing either.
    #expect(MultitouchDeviceKind.classify([
        "HIDPointerAccelerationType": 3,
        "DeviceUsagePairs": "none"
    ]) == .unknown)
}

@Test func classifiesBridgedFoundationValues() {
    let pairs = NSArray(array: [NSDictionary(dictionary: [
        "DeviceUsagePage": NSNumber(value: 13), "DeviceUsage": NSNumber(value: 5)
    ])])
    #expect(MultitouchDeviceKind.classify(["DeviceUsagePairs": pairs]) == .trackpad)
    #expect(MultitouchDeviceKind.classify(["HIDPointerAccelerationType": NSString(string: "HIDMouseAcceleration")])
        == .other)
}

@Test func registryEntriesMatchByIDBeforeBuiltInOrder() {
    var entries = MultitouchDevices.RegistryEntries(entries: [
        .init(multitouchID: 1, isBuiltIn: false, kind: .other),
        .init(multitouchID: 2, isBuiltIn: false, kind: .trackpad),
        .init(multitouchID: 3, isBuiltIn: true, kind: .trackpad)
    ])
    #expect(entries.take(id: 2, builtIn: false)?.kind == .trackpad)
    // Unknown ID: the first remaining entry with the same built-in flag.
    #expect(entries.take(id: 99, builtIn: false)?.multitouchID == 1)
    #expect(entries.take(id: nil, builtIn: true)?.multitouchID == 3)
    #expect(entries.take(id: nil, builtIn: true) == nil)
}
