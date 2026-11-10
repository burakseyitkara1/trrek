# Changelog

All notable changes to this project are documented in this file.

Each release lists its changes under its version and date; changes not yet released are listed under Unreleased.

## [Unreleased]

- Check for Updates in the menu works in place: the menu stays open, the row shows "Checking for Updates…" with a spinner, then "trrek Is Up to Date", "Couldn’t Check — Try Again" or the update itself, which downloads and installs from the same row; the separate update row at the top of the menu is gone, and a manual check never shows an alert

## [0.6.0] - 2026-11-10

- Set edges and corners right on the trackpad diagram: in the Edges tab each edge's label, and in Corners & Taps each corner's badge, opens a menu of its actions with Off first (Same as All Apps above it for an app's edges); the edge and corner pickers below the diagram are gone, and an edge or corner that cannot run its action yet shows a warning badge
- The trackpad diagram draws each edge's touch zone to scale with this Mac's trackpad, so Edge Width and Bottom Quarter Only show where a slide starts; the zones animate as either setting changes, and Edge Width has a caption explaining it. The diagram is quiet and neutral, and the edge or corner under the pointer lights up in the accent colour

## [0.5.3] - 2026-11-09

- A new app icon in the macOS 26 style: a frosted glass trackpad with a glowing edge on a deep blue rounded square
- The disk image opens as a styled window: trrek and the Applications shortcut side by side with an arrow and "Drag trrek to Applications"

## [0.5.2] - 2026-11-09

- General shows trrek's version and its update on one line: below the version it says whether an update is available, downloading or failed (and why), and the one button checks, updates, retries or relaunches; Check Now shows "trrek is up to date" or why the check failed on that line instead of in an alert

## [0.5.1] - 2026-11-09

- Updates retry on their own when GitHub is briefly unavailable (server errors, rate limits, timeouts, a dropped connection): up to two more tries, after 2 and 5 seconds; when an update still fails, General says why (GitHub isn't responding, you appear to be offline, or the update couldn't be verified)

## [0.5.0] - 2026-11-09

- Edges per app: in the Edges tab, Edges For gives an app its own edge actions (Switch Tabs on the top edge in a browser, Scrub Video in a video player), used while it is in front; the menu shows "Edges set for <app>" meanwhile, and a slide in progress is never interrupted by the switch

## [0.4.2] - 2026-11-09

- trrek is open source: its code and releases are on github.com/burakseyitkara1/trrek, and the update check now reads that repository's releases

## [0.4.1] - 2026-11-09

- The app is smaller: its executable ships without the build's symbol table and debug paths
- The update check reads at most 1 MB of release information and an update downloads at most 64 MB; anything larger is refused
- An update never installs, or downloads, a version older than the running one
- Error messages in the system log no longer contain file paths or device identifiers

## [0.4.0] - 2026-11-08

- trrek tells you when a newer version is out: it checks the public releases page at most once a day (after launch, after wake or when the menu opens) and shows an arrow on the menu bar icon and Update Available at the top of the menu
- Choosing Update Available updates trrek in the open menu: the row shows the download's progress, then trrek checks the new app's signature and notarization, replaces itself where it is and opens again; a failure shows Try Again, and when trrek can't replace itself the release page opens in the browser
- Check for Updates… in the menu, and Check for Updates Automatically, Check Now, the last check time and Update Now in General

## [0.3.0] - 2026-11-06

- Export Settings… and Import Settings… in the General tab save the settings to a `.trrek` file and load them back after a confirmation; opening a `.trrek` file from Finder offers the same import
- Every edge offers every action: the left and right edges get their own pickers in place of Swap Sides (a stored Swap Sides setting carries over), and the trackpad diagram shows them
- New edge actions: Switch Tabs, Switch Desktops, Zoom and Undo & Redo (forward is rightward on the top and bottom edges, upward on the side edges)
- New corner actions: Play/Pause, Mission Control, App Windows, Show Desktop, Spotlight, Lock Screen and Screenshot Area
- Slide Sensitivity setting in General: how far a finger slides for each step, from Very Low to Very High
- A corner's double tap keeps working when an edge next to it is set to Off
- Turkish interface, and a Language setting in General (System, English, Türkçe) that applies after a relaunch
- The Language setting follows a language chosen for trrek in System Settings › General › Language & Region › Applications

## [0.2.2] - 2026-11-04

- The line trrek logs when a signal makes it quit is kept in the system log, so a signal quit can be checked afterwards
- Paused Apps: the app chooser opens as a sheet on the settings window also when trrek was in the background

## [0.2.1] - 2026-11-04

- Haptics play on the trackpad you slide on, so an external trackpad gets its own feedback instead of the built-in one
- Keyboard backlight steps no longer wait for the level to be read back, so fast slides on the backlight edge stay smooth
- trrek quits cleanly when it receives SIGTERM or SIGINT, so Command is never left held down by the app switcher
- Opening trrek's settings, welcome or About window over a paused app keeps the edges paused (and over an active app keeps them active)
- Paused Apps: the app chooser opens as a sheet on the settings window, trrek itself can no longer be added, and app names and icons are looked up once

## [0.2.0] - 2026-11-04

- Scrub Video: slide the top or bottom edge to step through the video in the front app
- External monitor brightness over DDC/CI: the brightness edge follows the screen with the pointer
- Polish: welcome cards appear one after another (none with Reduce Motion), the overlay follows the pointer to another screen, the Edges tab says when the top or bottom action needs Accessibility, a single haptic at the keyboard backlight limit, the first-frame check ignores contacts that are not touching, and settings from older versions keep every readable field
- Fixes from the phase 2 review: overlay labels ("No DDC", scrub seconds) are no longer cut and replace the level bar; scrub sends no arrows to trrek's own windows; external displays without a DDC service use the brightness keys; the External Monitor Brightness setting says when it is not available; the first-frame check also rejects unknown contact states; a DDC failure is logged once
- One limit haptic at the end of a range, then silence: volume, built-in and external brightness and the keyboard backlight read their level before a step, skip steps past the bound and play step haptics again once the slide reverses or a new slide starts

## [0.1.1] - 2026-11-04

- Releases are signed with Developer ID, notarized and stapled (`make release`); the DMG has an Applications shortcut; local builds prefer a Developer ID identity

## [0.1.0] - 2026-11-04

- Fixes from the 0.1.0 review: trackpad-only devices, key timing, accessibility prompts and gating, toggle and limit haptics, first-frame check
- Cursor freeze: disconnect mouse movement from the cursor while sliding (swallowing pointer events alone did not stop it)
- Project scaffold: SPM package, Makefile, lint/format config, git hooks
- Packaging: app bundle build script, icon generation, CI and release workflows (Intel runner image)
- Platform: private symbol loader, raw multitouch stream, haptics, event posting, cursor-freeze tap and the TrrekProbe tool
- Engine: core types, configuration, command model and edge/corner geometry
- Engine: slide state machine with lost-finger recovery and watchdog
- Engine: corner and media double-taps, three-finger middle click
- Engine: palm, typing, hold-key and pause gates
- Engine: internal lock, clock contract, non-finite guard and step cap, bottom-quarter rule keeps corners, reset cancels
- CI: read-only token permissions
- Platform: gesture pipeline, command dispatcher and testable ports
- Platform: input monitor, hold-key tracker, keyboard backlight bridge and system observers
- App: settings store, coordinator, menu bar menu, launch at login
- App: Liquid Glass settings window
- App: level overlay and welcome window
- Release: manual test checklist, footprint-based perf check, optional stable signing identity, build argument validation, grouped dependabot updates
