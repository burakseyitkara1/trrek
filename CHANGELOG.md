# Changelog

All notable changes to this project are documented in this file.

Each release lists its changes under its version and date; changes not yet released are listed under Unreleased.

## [Unreleased]

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
