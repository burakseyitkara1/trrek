import Foundation

/// Why trrek cannot replace its own app bundle; the update is then installed from the disk image by hand.
public enum InstallLocationIssue: Equatable, Sendable {
    /// trrek does not run from an `.app` bundle (a development build or the test runner).
    case notAppBundle
    /// macOS runs trrek from a randomized read-only copy (App Translocation), because it was opened in place from
    /// a quarantined download.
    case translocated
    /// trrek runs from a mounted disk image.
    case diskImage
    /// trrek runs from a read-only volume.
    case readOnlyVolume
    /// trrek may not write to its bundle or to the folder holding it.
    case notWritable

    /// The explanation shown when the disk image is opened instead.
    public var message: String {
        switch self {
        case .notAppBundle:
            String(localized: "trrek isn’t running from an app bundle.", bundle: .main)
        case .translocated:
            String(
                localized: "macOS runs trrek from a temporary location. Move trrek to the Applications folder.",
                bundle: .main
            )
        case .diskImage, .readOnlyVolume:
            String(localized: "trrek runs from a disk image or a read-only volume.", bundle: .main)
        case .notWritable:
            String(localized: "trrek can’t write to the folder it’s installed in.", bundle: .main)
        }
    }
}

/// What the file system says about the running app bundle's location.
public struct InstallLocationFacts: Equatable, Sendable {
    /// The bundle is a folder named `*.app` with a `Contents/Info.plist`.
    public var isAppBundle: Bool
    /// The bundle's path, checked for App Translocation.
    public var path: String
    public var isOnDiskImage: Bool
    public var isOnReadOnlyVolume: Bool
    /// trrek may write to the bundle and to the folder holding it.
    public var isWritable: Bool

    public init(isAppBundle: Bool, path: String, isOnDiskImage: Bool, isOnReadOnlyVolume: Bool, isWritable: Bool) {
        self.isAppBundle = isAppBundle
        self.path = path
        self.isOnDiskImage = isOnDiskImage
        self.isOnReadOnlyVolume = isOnReadOnlyVolume
        self.isWritable = isWritable
    }
}

/// Why a staged update was refused. A refused update is never installed and the disk image is not opened.
public enum UpdateVerificationFailure: Error, Equatable, Sendable {
    /// The code signature is broken, or not trrek's Developer ID signature.
    case signature
    /// Gatekeeper did not accept the app (it is not notarized).
    case notNotarized
    /// The app is not trrek (another bundle identifier, or no readable `Info.plist`).
    case notTrrek
    /// The app's version is not the one the release names; carries the version found.
    case unexpectedVersion(String?)
    /// The app is not newer than the version the update check runs as.
    case notNewer

    /// The explanation shown in the "couldn't be verified" alert.
    public var message: String {
        switch self {
        case .signature:
            String(localized: "The update isn’t signed by trrek’s developer.", bundle: .main)
        case .notNotarized:
            String(localized: "macOS didn’t accept the update: it isn’t notarized.", bundle: .main)
        case .notTrrek:
            String(localized: "The disk image doesn’t contain trrek.", bundle: .main)
        case let .unexpectedVersion(found):
            String(localized: "The disk image contains another version (\(found ?? "?")).", bundle: .main)
        case .notNewer:
            String(localized: "The update isn’t newer than this version of trrek.", bundle: .main)
        }
    }
}

/// Why an update could not be installed in place.
public enum UpdateInstallError: Error, Equatable, Sendable {
    /// trrek cannot replace its bundle where it runs; the disk image is opened instead.
    case location(InstallLocationIssue)
    /// The disk image could not be mounted or the app not copied from it; the disk image is opened instead.
    case extraction
    /// The staged app failed verification; nothing is installed or opened.
    case verification(UpdateVerificationFailure)
    /// The bundle could not be replaced (the previous one is kept); the disk image is opened instead.
    case replacement

    /// Whether the disk image is opened for a manual install; only a failed verification does not.
    public var fallsBackToDiskImage: Bool {
        if case .verification = self {
            return false
        }
        return true
    }

    /// The explanation shown with the disk image fallback.
    public var message: String {
        switch self {
        case let .location(issue):
            issue.message
        case .extraction:
            String(localized: "The disk image couldn’t be opened.", bundle: .main)
        case let .verification(failure):
            failure.message
        case .replacement:
            String(localized: "The installed app couldn’t be replaced.", bundle: .main)
        }
    }
}

/// The decisions of the in-place install, free of the file system.
public enum UpdateInstallPolicy {
    /// The path component macOS gives translocated apps.
    public static let translocationMarker = "/AppTranslocation/"

    public static func isTranslocated(path: String) -> Bool {
        path.contains(translocationMarker)
    }

    /// Why the bundle the facts describe cannot be replaced in place; `nil` when it can.
    public static func issue(for facts: InstallLocationFacts) -> InstallLocationIssue? {
        if !facts.isAppBundle {
            return .notAppBundle
        }
        if isTranslocated(path: facts.path) {
            return .translocated
        }
        if facts.isOnDiskImage {
            return .diskImage
        }
        if facts.isOnReadOnlyVolume {
            return .readOnlyVolume
        }
        return facts.isWritable ? nil : .notWritable
    }

    /// Checks the staged app's `Info.plist` values: trrek's bundle identifier, the release's version and newer than
    /// `current` (the version the update check runs as, real or assumed). `nil` when all hold. The values are read
    /// only after the signature check, which seals `Info.plist`.
    public static func identityProblem(
        bundleID: String?,
        version: String?,
        expected: SemanticVersion,
        current: SemanticVersion
    ) -> UpdateVerificationFailure? {
        guard bundleID == AppIdentity.bundleID else { return .notTrrek }
        // The exact `X.Y.Z` text, so a `v` prefix or a suffix is refused too.
        guard version == expected.description else { return .unexpectedVersion(version) }
        return expected > current ? nil : .notNewer
    }
}
