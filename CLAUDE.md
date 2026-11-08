# trrek — project rules

trrek is a standalone macOS menu bar app that turns the edges of the trackpad into single-finger controls (volume, brightness, keyboard backlight, app switching, media). Design: `docs/superpowers/specs/`. Plans: `docs/superpowers/plans/`.

## Language and naming
- Everything in the project is in English: code, comments, commit messages, pull request titles and bodies, issues, documents and the interface.
- The interface is written in English and translated into Turkish in `tr.lproj`: `Sources/Trrek/Resources/{en,tr}.lproj/Localizable.strings`, keyed by the English source text. Every new interface string goes into both files; `LocalizationTests` catches missing keys, extra keys and mismatched format specifiers.
- The app's name is always lowercase: `trrek`. Bundle ID `com.burakseyitkara.trrek`.
- No other app, library or project is named anywhere in the project: not in code, comments, documents, commit messages or pull requests. No "reference", "inspired by" or "adapted from" credits. All code is written from scratch in this repository; nothing is copied from outside code.

## Technical limits
- Built with Swift Package Manager; there is no Xcode project. `swift-tools-version: 6.0`, Swift 6 language mode, macOS 26.0+, arm64 only.
- CI uses Xcode 26.6: no Swift 6.3+ language features and no macOS 27 APIs.
- Private framework symbols are resolved only in `Sources/TrrekPlatform/PrivateSymbols.swift`, with `dlopen`/`dlsym`; a missing symbol turns the feature off and never crashes.
- Performance budget: 0% CPU and under 15 MB of memory when idle; no heap allocation per frame; no periodic timers.
- UI: SwiftUI with macOS 26 Liquid Glass; windows are created when needed and released when closed.

## Git, pull requests and CI
- The repository is public (MIT). `main` is protected by rulesets: no direct pushes, no force pushes, no deletion; every change arrives through a pull request that is squash-merged with linear history, after the `build-test` check passes on a branch that is up to date with `main` and every review thread is resolved. Outside contributions also need the maintainer's approval (code owner); the maintainer's own pull requests may skip only that approval.
- Release tags `v*` can be created, moved or deleted only by the maintainer.
- Branch prefixes: `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, `test/`. Conventional commits.
- Pull request bodies follow `.github/pull_request_template.md`.
- `make check` (build, tests, format, lint) must pass locally before every push. Merges and releases are gated on its exit code (and on CI), never on filtered output.
- Each pull request with a user-visible change adds one line to `CHANGELOG.md` under "Unreleased".
- Releases: `make release VERSION=X.Y.Z` from an up-to-date `main` after a successful `ci` run on that commit.

## Tests
- Swift Testing; a synthetic-frame test for every gesture rule in `TrrekEngine`. Behaviour that needs hardware goes into the manual checklist, `docs/testing.md`.
- Tests never create real system alerts, panels or windows that need the window server's attention for long; a headless CI runner can stall on them.
- `TrrekProbe` is a development tool and is not part of the app bundle.
