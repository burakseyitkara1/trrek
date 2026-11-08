## Summary

<!-- What does this change do, and why? Link the issue it closes, e.g. "Closes #12". -->

## Type of change

- [ ] Feature
- [ ] Bug fix
- [ ] Performance
- [ ] Refactor
- [ ] Tests
- [ ] CI / build / release
- [ ] Documentation

## How it was tested

<!-- Automated tests added or changed, and any manual checks from docs/testing.md you ran (with the Mac model and macOS version). -->

## Checklist

- [ ] `make check` passes (build, tests, format, lint)
- [ ] Tests cover the change (gesture rules with synthetic frames in `Tests/TrrekEngineTests`)
- [ ] New interface strings are in both `en.lproj` and `tr.lproj`
- [ ] `docs/testing.md` is updated for behaviour that needs hardware
- [ ] No effect on the idle budget (0% CPU, under 15 MB), no per-frame allocation, no periodic timers
- [ ] One line added to `CHANGELOG.md` under "Unreleased" for a user-visible change
