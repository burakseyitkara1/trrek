import Foundation
import Testing
@testable import TrrekAppCore
import TrrekEngine

/// The in-place install's decisions, and the installer with fake steps: what runs, what fails and that the staging
/// folder never outlives an attempt.
struct UpdateInstallPolicyTests {
    private static let good = InstallLocationFacts(
        isAppBundle: true,
        path: "/Applications/trrek.app",
        isOnDiskImage: false,
        isOnReadOnlyVolume: false,
        isWritable: true
    )

    @Test func translocation() {
        #expect(UpdateInstallPolicy.isTranslocated(path: "/private/var/folders/x/AppTranslocation/1F2/d/trrek.app"))
        #expect(!UpdateInstallPolicy.isTranslocated(path: "/Applications/trrek.app"))
        #expect(!UpdateInstallPolicy.isTranslocated(path: "/Users/me/AppTranslocation.app"))
    }

    @Test func locationIssues() {
        #expect(UpdateInstallPolicy.issue(for: Self.good) == nil)
        var facts = Self.good
        facts.isWritable = false
        #expect(UpdateInstallPolicy.issue(for: facts) == .notWritable)
        facts.isOnReadOnlyVolume = true
        #expect(UpdateInstallPolicy.issue(for: facts) == .readOnlyVolume)
        facts.isOnDiskImage = true
        #expect(UpdateInstallPolicy.issue(for: facts) == .diskImage)
        facts.path = "/private/var/folders/x/AppTranslocation/1F2/d/trrek.app"
        #expect(UpdateInstallPolicy.issue(for: facts) == .translocated)
        facts.isAppBundle = false
        #expect(UpdateInstallPolicy.issue(for: facts) == .notAppBundle)
    }

    @Test func identity() throws {
        let v030 = try #require(SemanticVersion("0.3.0"))
        let v020 = try #require(SemanticVersion("0.2.0"))
        let id = AppIdentity.bundleID
        func problem(_ bundleID: String?, _ version: String?, current: SemanticVersion) -> UpdateVerificationFailure? {
            UpdateInstallPolicy.identityProblem(bundleID: bundleID, version: version, expected: v030, current: current)
        }
        #expect(problem(id, "0.3.0", current: v020) == nil)
        #expect(problem("com.example.other", "0.3.0", current: v020) == .notTrrek)
        #expect(problem(nil, nil, current: v020) == .notTrrek)
        #expect(problem(id, "0.3.1", current: v020) == .unexpectedVersion("0.3.1"))
        #expect(problem(id, "v0.3.0", current: v020) == .unexpectedVersion("v0.3.0"))
        #expect(problem(id, nil, current: v020) == .unexpectedVersion(nil))
        #expect(problem(id, "0.3.0", current: v030) == .notNewer)
        #expect(try problem(id, "0.3.0", current: #require(SemanticVersion("0.4.0"))) == .notNewer)
    }

    /// A version below the running one is refused whatever the update check assumes; the same version is allowed.
    @Test func downgrades() throws {
        let running = try #require(SemanticVersion("0.4.0"))
        func problem(_ version: String) throws -> UpdateVerificationFailure? {
            try UpdateInstallPolicy.downgradeProblem(version: #require(SemanticVersion(version)), running: running)
        }
        #expect(try problem("0.3.9") == .olderThanRunning)
        #expect(try problem("0.4.0") == nil)
        #expect(try problem("0.4.1") == nil)
        #expect(UpdateInstaller.runningVersion.description == TrrekVersion.string)
    }

    @Test func onlyAFailedVerificationDoesNotOpenTheReleasePage() {
        #expect(UpdateInstallError.location(.translocated).fallsBackToBrowser)
        #expect(UpdateInstallError.extraction.fallsBackToBrowser)
        #expect(UpdateInstallError.replacement.fallsBackToBrowser)
        #expect(!UpdateInstallError.verification(.signature).fallsBackToBrowser)
    }
}

@Suite(.serialized)
struct UpdateInstallerTests {
    private static let bundle = URL(fileURLWithPath: "/Applications/trrek.app")

    private struct Harness {
        let installer: UpdateInstaller
        let log: Log
        let location: Location
        let root: URL

        /// The staging folders created and still present.
        var stagingFolders: [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        }
    }

    private static func harness(
        extractError: (any Error)? = nil,
        verifications: [UpdateVerificationFailure?] = [],
        replaceFails: Bool = false,
        running: SemanticVersion = v040
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trrek-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = Log()
        let location = Location()
        let installer = UpdateInstaller(
            bundle: bundle,
            extractor: Extractor(log: log, error: extractError),
            verifier: Verifier(log: log, answers: verifications),
            replacer: Replacer(log: log, fails: replaceFails),
            location: location,
            makeStagingFolder: { _ in
                let folder = root.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                return folder
            },
            runningVersion: running
        )
        return Harness(installer: installer, log: log, location: location, root: root)
    }

    private static let image = URL(fileURLWithPath: "/tmp/trrek-v0.4.0.dmg")
    private static let v040 = SemanticVersion(major: 0, minor: 4, patch: 0)
    private static let v030 = SemanticVersion(major: 0, minor: 3, patch: 0)
    private static let prepared = ["sweep mounts", "extract", "verify staged"]

    private static func prepare(_ harness: Harness) async -> Result<StagedUpdate, UpdateInstallError> {
        do {
            return try await .success(harness.installer.prepare(image: image, version: v040, current: v030))
        } catch {
            return .failure(error)
        }
    }

    private static func install(_ harness: Harness, _ staged: StagedUpdate) async -> UpdateInstallError? {
        do {
            try await harness.installer.install(staged)
            return nil
        } catch {
            return error
        }
    }

    @Test func stagesVerifiesAndReplaces() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let staged = try await Self.prepare(harness).get()
        #expect(staged.version == Self.v040)
        #expect(staged.current == Self.v030)
        #expect(staged.app.lastPathComponent == "trrek.app")
        #expect(harness.stagingFolders.count == 1)
        #expect(harness.log.all == Self.prepared)

        #expect(await Self.install(harness, staged) == nil)
        #expect(harness.log.all == Self.prepared + [
            "unquarantine", "verify staged", "swap", "verify installed", "remove backup"
        ])
        #expect(harness.stagingFolders.isEmpty)
    }

    /// The staged app changed while the alert was shown: it passed when prepared and fails right before the swap.
    @Test func aStagedAppChangedSincePreparingIsNotInstalled() async throws {
        let harness = try Self.harness(verifications: [nil, .signature])
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let staged = try await Self.prepare(harness).get()
        #expect(await Self.install(harness, staged) == .verification(.signature))
        #expect(harness.log.all == Self.prepared + ["unquarantine", "verify staged"])
        #expect(harness.stagingFolders.isEmpty)
    }

    /// The app in place after the swap fails verification: the previous app is put back.
    @Test func anInstalledAppThatFailsIsRolledBack() async throws {
        let harness = try Self.harness(verifications: [nil, nil, .notNotarized])
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let staged = try await Self.prepare(harness).get()
        #expect(await Self.install(harness, staged) == .verification(.notNotarized))
        #expect(harness.log.all.suffix(3) == ["swap", "verify installed", "restore"])
        #expect(!harness.log.all.contains("remove backup"))
        #expect(harness.stagingFolders.isEmpty)
    }

    @Test func aLocationIssueStopsBeforeMounting() async throws {
        for issue in [InstallLocationIssue.notAppBundle, .translocated, .diskImage, .readOnlyVolume, .notWritable] {
            let harness = try Self.harness()
            defer { try? FileManager.default.removeItem(at: harness.root) }
            harness.location.issue = issue
            #expect(await harness.installer.locationIssue() == issue)
            guard case let .failure(error) = await Self.prepare(harness) else {
                Issue.record("expected a failure for \(issue)")
                continue
            }
            #expect(error == .location(issue))
            #expect(harness.log.all.isEmpty)
            #expect(harness.stagingFolders.isEmpty)
        }
    }

    @Test func aFailedExtractionCleansUp() async throws {
        let harness = try Self.harness(extractError: URLError(.cannotOpenFile))
        defer { try? FileManager.default.removeItem(at: harness.root) }
        guard case let .failure(error) = await Self.prepare(harness) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error == .extraction)
        #expect(harness.log.all == ["sweep mounts", "extract"])
        #expect(harness.stagingFolders.isEmpty)
    }

    /// A disk image not signed by the release team is a verification failure: it is neither mounted nor opened.
    @Test func anUnsignedDiskImageIsRefused() async throws {
        let harness = try Self.harness(extractError: UpdateVerificationFailure.signature)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        guard case let .failure(error) = await Self.prepare(harness) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error == .verification(.signature))
        #expect(!error.fallsBackToBrowser)
        #expect(harness.stagingFolders.isEmpty)
    }

    @Test func aFailedVerificationCleansUp() async throws {
        for failure in [UpdateVerificationFailure.signature, .notNotarized, .notTrrek, .unexpectedVersion("1.0.0")] {
            let harness = try Self.harness(verifications: [failure])
            defer { try? FileManager.default.removeItem(at: harness.root) }
            guard case let .failure(error) = await Self.prepare(harness) else {
                Issue.record("expected a failure for \(failure)")
                continue
            }
            #expect(error == .verification(failure))
            #expect(harness.log.all == Self.prepared)
            #expect(harness.stagingFolders.isEmpty)
        }
    }

    /// Under `--assume-version` the check may offer a release older than the running trrek: it is refused before
    /// anything is mounted, and a staged one before the swap.
    @Test func anOlderVersionThanTheRunningOneIsRefused() async throws {
        let harness = try Self.harness(running: SemanticVersion(major: 0, minor: 5, patch: 0))
        defer { try? FileManager.default.removeItem(at: harness.root) }
        guard case let .failure(error) = await Self.prepare(harness) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error == .verification(.olderThanRunning))
        #expect(!error.fallsBackToBrowser)
        #expect(harness.log.all.isEmpty)
        #expect(harness.stagingFolders.isEmpty)

        let folder = harness.root.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = StagedUpdate(
            app: folder.appendingPathComponent("trrek.app"),
            folder: folder,
            version: Self.v040,
            current: Self.v030
        )
        #expect(await Self.install(harness, staged) == .verification(.olderThanRunning))
        #expect(harness.log.all.isEmpty)
        #expect(harness.stagingFolders.isEmpty)
    }

    @Test func aFailedReplaceCleansUp() async throws {
        let harness = try Self.harness(replaceFails: true)
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let staged = try await Self.prepare(harness).get()
        #expect(await Self.install(harness, staged) == .replacement)
        #expect(harness.stagingFolders.isEmpty)
        #expect(!harness.log.all.contains("verify installed"))
    }

    /// The app moved to a place it cannot be replaced while the alert was shown.
    @Test func theLocationIsCheckedAgainBeforeReplacing() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let staged = try await Self.prepare(harness).get()
        harness.location.issue = .notWritable
        #expect(await Self.install(harness, staged) == .location(.notWritable))
        #expect(!harness.log.all.contains("swap"))
        #expect(harness.stagingFolders.isEmpty)
    }

    /// Staging folders an interrupted run left next to the new one (holding only a `trrek.app`) are removed; other
    /// folders there are kept.
    @Test func leftoverStagingIsRemovedBeforePreparing() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let manager = FileManager.default
        let stale = harness.root.appendingPathComponent("stale/trrek.app")
        try manager.createDirectory(at: stale, withIntermediateDirectories: true)
        let other = harness.root.appendingPathComponent("other/file")
        try manager.createDirectory(at: other, withIntermediateDirectories: true)

        let staged = try await Self.prepare(harness).get()

        #expect(!manager.fileExists(atPath: stale.deletingLastPathComponent().path))
        #expect(manager.fileExists(atPath: other.path))
        #expect(manager.fileExists(atPath: staged.app.path))
    }

    @Test func leftoversAreCleanedAtLaunch() async throws {
        let harness = try Self.harness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        await harness.installer.cleanUpLeftovers()
        #expect(harness.log.all == ["sweep mounts", "remove backup"])
    }
}

// MARK: - Fakes

extension UpdateInstallerTests {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []

        func add(_ entry: String) {
            lock.withLock { entries.append(entry) }
        }

        var all: [String] {
            lock.withLock { entries }
        }
    }

    private struct Extractor: DiskImageAppExtracting {
        let log: Log
        let error: (any Error)?

        func extractApp(from _: URL, into folder: URL) async throws -> URL {
            log.add("extract")
            if let error {
                throw error
            }
            let app = folder.appendingPathComponent("trrek.app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            return app
        }

        func cleanUpLeftovers() async {
            log.add("sweep mounts")
        }
    }

    /// Answers each verification in turn with the next of `answers` (then passes).
    private final class Verifier: UpdateVerifying, @unchecked Sendable {
        let log: Log
        private let lock = NSLock()
        private var answers: [UpdateVerificationFailure?]

        init(log: Log, answers: [UpdateVerificationFailure?]) {
            self.log = log
            self.answers = answers
        }

        func verify(
            _ app: URL,
            expected _: SemanticVersion,
            current _: SemanticVersion
        ) async -> UpdateVerificationFailure? {
            log.add(app == UpdateInstallerTests.bundle ? "verify installed" : "verify staged")
            return lock.withLock { answers.isEmpty ? nil : answers.removeFirst() }
        }
    }

    private struct Replacer: BundleReplacing {
        let log: Log
        let fails: Bool

        func removeQuarantine(in _: URL) async {
            log.add("unquarantine")
        }

        func swap(_ bundle: URL, with staged: URL) async throws -> URL {
            log.add("swap")
            #expect(FileManager.default.fileExists(atPath: staged.path))
            if fails {
                throw CocoaError(.fileWriteNoPermission)
            }
            return BundleReplacer.backup(for: bundle)
        }

        func restore(_: URL, from _: URL) async throws {
            log.add("restore")
        }

        func removeBackup(next _: URL) async {
            log.add("remove backup")
        }
    }

    private final class Location: InstallLocationInspecting, @unchecked Sendable {
        var issue: InstallLocationIssue?

        func facts(for bundle: URL) -> InstallLocationFacts {
            InstallLocationFacts(
                isAppBundle: issue != .notAppBundle,
                path: issue == .translocated ? "/x/AppTranslocation/y/trrek.app" : bundle.path,
                isOnDiskImage: issue == .diskImage,
                isOnReadOnlyVolume: issue == .readOnlyVolume,
                isWritable: issue != .notWritable
            )
        }
    }
}
