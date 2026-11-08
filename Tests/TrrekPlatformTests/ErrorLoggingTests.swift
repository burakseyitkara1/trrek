import Foundation
import Testing
import TrrekPlatform

/// What a logged error shows publicly: its domain and code, never the description with its file path.
struct ErrorLoggingTests {
    @Test func onlyTheDomainAndCodeArePublic() {
        let error = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/me/Library/Caches/x.dmg"])
        #expect(error.domainAndCode == "NSCocoaErrorDomain 4")
        #expect(String(describing: error).contains("/Users/me"))
        #expect(URLError(.timedOut).domainAndCode == "NSURLErrorDomain -1001")
    }
}
