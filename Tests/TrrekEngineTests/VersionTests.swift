import Testing
@testable import TrrekEngine

@Test func versionStringIsSemver() {
    let parts = TrrekVersion.string.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
