# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

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
