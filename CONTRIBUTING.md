# Contributing to trrek

Thanks for your interest. trrek is a small macOS menu bar app; issues and pull requests are welcome.

## Before you start

- trrek targets macOS 26 or later on Apple silicon and builds with Swift Package Manager only (no Xcode project). Swift 6 language mode; please don't use Swift 6.3+ language features or macOS 27 APIs, since CI builds with Xcode 26.6.
- Read `docs/superpowers/specs/2026-11-03-trrek-design.md` for the architecture and `docs/decisions.md` for why things are the way they are. Project documents and decision records are written in Turkish; code, comments, commit messages and the interface are in English.
- Private system symbols live only in `Sources/TrrekPlatform/PrivateSymbols.swift` and are resolved at run time; a missing symbol must turn a feature off, never crash.
- Performance budget: 0% CPU and under 15 MB of memory when idle, no heap allocation per trackpad frame, no periodic timers.

## Making a change

1. Install the tools: `brew install swiftlint swiftformat`, then `make hooks`.
2. Create a branch: `feat/`, `fix/`, `docs/`, `ci/`, `chore/` or `test/`.
3. Add tests. Gesture rules are tested with synthetic frames in `Tests/TrrekEngineTests`; behaviour that needs hardware goes in the manual checklist, `docs/testing.md`.
4. Every new interface string goes into both `Sources/Trrek/Resources/en.lproj/Localizable.strings` and `tr.lproj/Localizable.strings`.
5. Add one line to `CHANGELOG.md` under "Unreleased".
6. Run `make check` (build, tests, format, lint) and open a pull request with a conventional commit title.

## Reporting bugs

Please include your Mac model, macOS version, trrek version (About trrek) and whether you use the built-in or an external trackpad.
