import Foundation
import os

public extension Error {
    /// The error's domain and code (for example `NSCocoaErrorDomain 4`), which may be logged publicly. Its description
    /// is logged privately only: a Cocoa or URL error's carries file paths (with the user's name) and addresses.
    var domainAndCode: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}

public extension Logger {
    /// Logs `what` and `error`: its domain and code publicly, its description privately. `what` is logged
    /// publicly, so pass only fixed text: never interpolate paths, names, URLs or other user data into it.
    func error(_ what: String, _ error: any Error) {
        let code = error.domainAndCode
        let description = String(describing: error)
        self.error("\(what, privacy: .public): \(code, privacy: .public) \(description, privacy: .private)")
    }

    /// `error(_:_:)` at the fault level.
    func fault(_ what: String, _ error: any Error) {
        let code = error.domainAndCode
        let description = String(describing: error)
        fault("\(what, privacy: .public): \(code, privacy: .public) \(description, privacy: .private)")
    }
}
