import Foundation
import Testing
@testable import TrrekAppCore

/// The menu's update row: its states, texts and transitions, for manual and automatic checks.
struct MenuUpdateRowStateTests {
    private static let version = SemanticVersion(major: 0, minor: 4, patch: 0)

    @Test func idleLooksLikeAnOrdinaryItem() {
        let row = MenuUpdateRowState()
        #expect(row.phase == .idle)
        #expect(row.title == "Check for Updates")
        #expect(row.icon == .none)
        #expect(!row.isProminent)
        #expect(row.isClickable)
        #expect(!row.showsProgressBar)
        #expect(row.failureReason == nil)
        #expect(row.accessibilityLabel == "Check for Updates")
    }

    @Test func aManualCheckThatFindsNothing() {
        var row = MenuUpdateRowState()
        #expect(row.click() == .check)
        #expect(row.phase == .checking)
        #expect(row.title == "Checking for Updates…")
        #expect(row.icon == .spinner)
        #expect(!row.isClickable)
        // A second click (or Return) while checking does nothing.
        #expect(row.click() == .nothing)

        // The controller reports its own check starting and ending; the row keeps checking until the outcome.
        row.show(update: nil, isCheckRunning: true)
        row.show(update: nil, isCheckRunning: false)
        #expect(row.phase == .checking)

        row.finishCheck(.upToDate, update: nil)
        #expect(row.phase == .upToDate)
        #expect(row.title == "trrek Is Up to Date")
        #expect(row.icon == .checkmark)
        // A statement, not a command.
        #expect(!row.isClickable)
        #expect(row.click() == .nothing)

        row.menuClosed()
        #expect(row.phase == .idle)
    }

    @Test func aFailedCheckSaysWhyAndClickingChecksAgain() {
        var row = MenuUpdateRowState()
        _ = row.click()
        row.finishCheck(.checkFailed(message: "You appear to be offline."), update: nil)
        #expect(row.phase == .checkFailed(reason: "You appear to be offline."))
        #expect(row.title == "Couldn’t Check — Try Again")
        #expect(row.icon == .warning)
        #expect(row.failureReason == "You appear to be offline.")
        #expect(row.accessibilityLabel == "Couldn’t Check — Try Again. You appear to be offline.")
        #expect(row.isClickable)

        #expect(row.click() == .check)
        #expect(row.phase == .checking)
        row.finishCheck(.checkFailed(message: ""), update: nil)
        #expect(row.failureReason == nil)
        row.menuClosed()
        #expect(row.phase == .idle)
    }

    @Test func aManualCheckThatFindsAnUpdate() {
        var row = MenuUpdateRowState()
        _ = row.click()
        // The found release reaches the row as soon as the controller knows it.
        row.show(update: .available(Self.version), isCheckRunning: false)
        #expect(row.phase == .update(.available(Self.version)))
        row.finishCheck(nil, update: .available(Self.version))
        #expect(row.phase == .update(.available(Self.version)))
        #expect(row.title == "Update Available: trrek 0.4.0")
        #expect(row.icon == .update)
        #expect(row.isProminent)
        #expect(row.isClickable)
        #expect(row.click() == .update)
        // The update outlives the menu.
        row.menuClosed()
        #expect(row.phase == .update(.available(Self.version)))
    }

    /// An automatic check never shows the spinner or its outcome; meanwhile the idle row waits, and a found update
    /// takes it over in place.
    @Test func automaticChecks() {
        var row = MenuUpdateRowState()
        row.show(update: nil, isCheckRunning: true)
        #expect(row.phase == .idle)
        #expect(row.icon == .none)
        #expect(!row.isClickable)
        #expect(row.click() == .nothing)
        row.show(update: nil, isCheckRunning: false)
        #expect(row.phase == .idle)
        #expect(row.isClickable)

        row.show(update: nil, isCheckRunning: true)
        row.show(update: .available(Self.version), isCheckRunning: false)
        #expect(row.phase == .update(.available(Self.version)))

        // A check that runs while the update is known does not hold up its click.
        row.show(update: .available(Self.version), isCheckRunning: true)
        #expect(row.click() == .update)

        // The update went away (a later check no longer offers it): back to checking for one.
        row.show(update: nil, isCheckRunning: false)
        #expect(row.phase == .idle)
    }

    /// A check's outcome that arrives after its menu closed (Return closes the menu) waits for the next menu.
    @Test func anOutcomeAfterTheMenuClosedShowsNextTime() {
        var row = MenuUpdateRowState()
        row.menuClosed()
        #expect(row.click() == .check)
        row.menuClosed()
        #expect(row.phase == .checking)
        row.finishCheck(.upToDate, update: nil)
        #expect(row.phase == .upToDate)
        row.menuClosed()
        #expect(row.phase == .idle)

        // A check that did not run (another had just started) ends without an outcome.
        _ = row.click()
        row.finishCheck(nil, update: nil)
        #expect(row.phase == .idle)
        // A late outcome does not replace a state the row has moved on to.
        row.finishCheck(.upToDate, update: nil)
        #expect(row.phase == .idle)
    }

    @Test func theUpdateStatesFollowTheDownload() {
        var row = MenuUpdateRowState(update: .downloading(Self.version, progress: nil))
        #expect(row.showsProgressBar && row.progress == nil)
        #expect(!row.isClickable)
        #expect(row.click() == .nothing)
        row.show(update: .downloading(Self.version, progress: 0.5), isCheckRunning: false)
        #expect(row.showsProgressBar && row.progress == 0.5)
        row.show(update: .installing(Self.version), isCheckRunning: false)
        #expect(row.showsProgressBar && row.progress == nil)
        #expect(row.title == "Installing trrek 0.4.0…")
        row.show(update: .failed(Self.version, reason: .offline), isCheckRunning: false)
        #expect(!row.showsProgressBar)
        #expect(row.failureReason == "You appear to be offline.")
        #expect(row.click() == .update)
    }

    /// The width samples hold every title the row can show while the menu is open: each state, for the known update
    /// and for the widest likely version.
    @Test func widthSamplesCoverEveryState() {
        let known = SemanticVersion(major: 1, minor: 2, patch: 3)
        let titles = Set(MenuUpdateRowState.widthSamples(known: known).map(\.title))
        let rows: [UpdateRowState] = [
            .available(known), .downloading(known, progress: nil), .installing(known), .failed(known),
            .browser(known), .relaunch(known)
        ]
        let wide = MenuUpdateRowState.widestVersion
        for title in [
            "Check for Updates", "Checking for Updates…", "trrek Is Up to Date", "Couldn’t Check — Try Again",
            "Update Available: trrek \(wide)", "Downloading trrek \(wide)…", "Installing trrek \(wide)…"
        ] + rows.map(\.title) {
            #expect(titles.contains(title), "\(title)")
        }
        #expect(MenuUpdateRowState.widthSamples(known: nil).count == 10)
        #expect(MenuUpdateRowState.widthSamples(known: wide).count == 10)
        #expect(MenuUpdateRowState.widthSamples(known: known).count == 16)
    }

    @Test func outcomeNotes() {
        #expect(UpdateCheckOutcome.upToDate.note == "trrek is up to date")
        #expect(UpdateCheckOutcome.checkFailed(message: "Offline.").note == "Offline.")
    }
}
