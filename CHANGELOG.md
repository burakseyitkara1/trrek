# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

- Scrub Video: slide the top or bottom edge to step through the video in the front app
- External monitor brightness over DDC/CI: the brightness edge follows the screen with the pointer

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
