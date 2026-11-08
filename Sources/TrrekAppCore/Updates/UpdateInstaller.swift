import Foundation

/// Mounts a disk image read-only and hidden, copies its `trrek.app` and detaches it; replaced by a fake in tests.
public protocol DiskImageAppExtracting: Sendable {
    /// Copies the app in `image` into `folder` and returns the copy. The image is detached on every path. Throws
    /// `UpdateVerificationFailure` when the image itself is not signed by the release team.
    func extractApp(from image: URL, into folder: URL) async throws -> URL

    /// Ejects images an interrupted run left mounted.
    func cleanUpLeftovers() async
}

/// Checks a staged app before it is installed; replaced by a fake in tests.
public protocol UpdateVerifying: Sendable {
    /// Why `app` must not be installed as version `expected` over `current`; `nil` when it may.
    func verify(_ app: URL, expected: SemanticVersion, current: SemanticVersion) async -> UpdateVerificationFailure?
}

/// Swaps the running app bundle for the staged one; replaced by a fake in tests.
public protocol BundleReplacing: Sendable {
    /// Removes the quarantine attribute from every file of the staged app.
    func removeQuarantine(in staged: URL) async

    /// Moves `staged` to `bundle` and keeps the previous app as a backup next to it, which it returns. When it throws,
    /// the previous app has been put back at `bundle` when it could be found (and the failure logged when not).
    func swap(_ bundle: URL, with staged: URL) async throws -> URL

    /// Puts the backup back at `bundle`, removing the app installed there.
    func restore(_ bundle: URL, from backup: URL) async throws

    /// Removes the backup next to `bundle`, also one an interrupted install left.
    func removeBackup(next bundle: URL) async
}

/// Reads the facts `UpdateInstallPolicy.issue(for:)` decides on; replaced by a fake in tests.
public protocol InstallLocationInspecting: Sendable {
    func facts(for bundle: URL) -> InstallLocationFacts
}

/// A verified app between `prepare` and `install`. `folder` is its staging folder, removed by `install`; `current` is
/// the version it was verified to be newer than.
public struct StagedUpdate: Equatable, Sendable {
    public let app: URL
    public let folder: URL
    public let version: SemanticVersion
    public let current: SemanticVersion

    public init(app: URL, folder: URL, version: SemanticVersion, current: SemanticVersion) {
        self.app = app
        self.folder = folder
        self.version = version
        self.current = current
    }
}

/// Prepares and installs a downloaded update; replaced by a fake in the controller's tests.
public protocol UpdateInstalling: Sendable {
    /// Checks that trrek can replace itself, copies the app out of `image` and verifies it as `version`, newer than
    /// `current`. Nothing is left mounted or staged when it throws.
    func prepare(
        image: URL,
        version: SemanticVersion,
        current: SemanticVersion
    ) async throws(UpdateInstallError) -> StagedUpdate

    /// Verifies the staged app again, replaces the running bundle with it and verifies the installed app, putting the
    /// previous one back if that fails. The staging folder is removed on every path.
    func install(_ staged: StagedUpdate) async throws(UpdateInstallError)

    /// Why trrek cannot replace its bundle where it runs; `nil` when it can. Asked before downloading, so a location
    /// that rules the install out sends the user to the release page at once (`prepare` asks again).
    func locationIssue() async -> InstallLocationIssue?

    /// Removes what an interrupted install left: mounted images and the previous app's backup.
    func cleanUpLeftovers() async
}

/// Installs an update over the app bundle at `bundle`: stage, verify, then replace.
public struct UpdateInstaller: UpdateInstalling {
    public let bundle: URL
    private let extractor: any DiskImageAppExtracting
    private let verifier: any UpdateVerifying
    private let replacer: any BundleReplacing
    private let location: any InstallLocationInspecting
    private let makeStagingFolder: @Sendable (URL) throws -> URL

    public init(
        bundle: URL,
        extractor: any DiskImageAppExtracting = DiskImageAppExtractor(),
        verifier: any UpdateVerifying = CodeSignatureVerifier(),
        replacer: any BundleReplacing = BundleReplacer(),
        location: any InstallLocationInspecting = SystemInstallLocation(),
        makeStagingFolder: @escaping @Sendable (URL) throws -> URL = UpdateInstaller.stagingFolder(for:)
    ) {
        self.bundle = bundle
        self.extractor = extractor
        self.verifier = verifier
        self.replacer = replacer
        self.location = location
        self.makeStagingFolder = makeStagingFolder
    }

    /// A fresh temporary folder on the same volume as `bundle`, so the staged app is moved into place, not copied.
    public static func stagingFolder(for bundle: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: bundle,
            create: true
        )
    }

    /// Why trrek cannot replace `bundle` now; `nil` when it can.
    public func locationIssue() async -> InstallLocationIssue? {
        let location = location
        let bundle = bundle
        do {
            return try await runOffMain { UpdateInstallPolicy.issue(for: location.facts(for: bundle)) }
        } catch {
            // The work does not throw; were it to, nothing was checked.
            return .notAppBundle
        }
    }

    public func prepare(
        image: URL,
        version: SemanticVersion,
        current: SemanticVersion
    ) async throws(UpdateInstallError) -> StagedUpdate {
        if let issue = await locationIssue() {
            appLogger.notice("update install not possible here: \(String(describing: issue), privacy: .public)")
            throw .location(issue)
        }
        await extractor.cleanUpLeftovers()
        let folder: URL
        let app: URL
        do {
            let makeStagingFolder = makeStagingFolder
            let bundle = bundle
            folder = try await runOffMain { try makeStagingFolder(bundle) }
        } catch {
            appLogger.error("update staging failed: \(String(describing: error), privacy: .public)")
            throw .extraction
        }
        await Self.removeStaleStaging(besides: folder)
        do {
            app = try await extractor.extractApp(from: image, into: folder)
        } catch let failure as UpdateVerificationFailure {
            appLogger.error("update disk image refused: \(String(describing: failure), privacy: .public)")
            await Self.remove(folder)
            throw .verification(failure)
        } catch {
            appLogger.error("update extraction failed: \(String(describing: error), privacy: .public)")
            await Self.remove(folder)
            throw .extraction
        }
        if let failure = await verifier.verify(app, expected: version, current: current) {
            appLogger.error("update verification failed: \(String(describing: failure), privacy: .public)")
            await Self.remove(folder)
            throw .verification(failure)
        }
        appLogger.notice("update \(version, privacy: .public) verified")
        return StagedUpdate(app: app, folder: folder, version: version, current: current)
    }

    public func install(_ staged: StagedUpdate) async throws(UpdateInstallError) {
        do {
            try await replace(with: staged)
        } catch {
            await Self.remove(staged.folder)
            throw error
        }
        await Self.remove(staged.folder)
        appLogger.notice("update \(staged.version, privacy: .public) installed")
    }

    /// The staged app sits in a folder any process of the user may write to between `prepare` and `install`, so it is
    /// verified again right before the swap (after the quarantine removal, which leaves the seal intact), and the
    /// installed app
    /// once more right after it.
    private func replace(with staged: StagedUpdate) async throws(UpdateInstallError) {
        // The app may have been moved since `prepare`.
        if let issue = await locationIssue() {
            appLogger.notice("update install not possible here: \(String(describing: issue), privacy: .public)")
            throw .location(issue)
        }
        await replacer.removeQuarantine(in: staged.app)
        if let failure = await verifier.verify(staged.app, expected: staged.version, current: staged.current) {
            appLogger.error("staged update changed: \(String(describing: failure), privacy: .public)")
            throw .verification(failure)
        }
        let backup: URL
        do {
            backup = try await replacer.swap(bundle, with: staged.app)
        } catch {
            appLogger.error("update replace failed: \(String(describing: error), privacy: .public)")
            throw .replacement
        }
        if let failure = await verifier.verify(bundle, expected: staged.version, current: staged.current) {
            appLogger.error("installed update failed verification: \(String(describing: failure), privacy: .public)")
            do {
                try await replacer.restore(bundle, from: backup)
            } catch {
                appLogger.fault("update rollback failed: \(String(describing: error), privacy: .public)")
            }
            throw .verification(failure)
        }
        await replacer.removeBackup(next: bundle)
    }

    public func cleanUpLeftovers() async {
        await extractor.cleanUpLeftovers()
        await replacer.removeBackup(next: bundle)
    }

    static func remove(_ folder: URL) async {
        do {
            try await runOffMain { try FileManager.default.removeItem(at: folder) }
        } catch {
            appLogger.error("update staging cleanup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes the staging folders of interrupted installs next to `folder`: those holding only a `trrek.app`.
    static func removeStaleStaging(besides folder: URL) async {
        _ = try? await runOffMain {
            let manager = FileManager.default
            let parent = folder.deletingLastPathComponent()
            let names = (try? manager.contentsOfDirectory(atPath: parent.path)) ?? []
            for name in names where name != folder.lastPathComponent {
                let sibling = parent.appendingPathComponent(name)
                guard (try? manager.contentsOfDirectory(atPath: sibling.path)) == [DiskImageAppExtractor.appName]
                else { continue }
                appLogger.notice("removing the leftover update staging folder \(name, privacy: .public)")
                try? manager.removeItem(at: sibling)
            }
        }
    }
}
