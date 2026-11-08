# Phase 0 Spike Results (TrrekProbe)

Date: 2026-11-03 · Machine: development Mac, macOS 27.2 · Tool: `TrrekProbe` (debug build)

| # | Question (spec 11) | Result | Decision |
|---|---|---|---|
| 1 | `MTTouch` layout and surface unit | 96 bytes, verified at compile time (`_Static_assert`). In a 90 s live stream: `nx` 0.41–0.84, `ny` 0.00–0.91, fingertip `major` 8–11.6 mm, `minor` 5–8.7 mm; `state` values 1,2,3,4,5,6,7 as expected. Surface `12194×7408` → 1/100 mm → 121.94×74.08 mm. | Layout and unit are correct; `MultitouchDevices` divides by 100. |
| 2 | Zero-touch frame on lift-off | On every lift-off the stream goes `state=5` (break) → `6` → `7` (major/minor 0) and then an `n=0` frame arrives; after that the device sleeps (9 gaps in 90 s; frame interval 8 ms = 125 Hz). | The platform puts only state 3/4 into `Frame`; a finger disappears at state 5 → `lost`. The watchdog stays as a fallback. Hover (state 1/2) does not count as a second finger. |
| 3 | Haptic waveforms | `actuate 4/5/6` → `ok` (return 0). The user picks the feel in settings. | Light→4, Medium→5, Strong→6 (initial); changeable from the settings window. |
| 4 | Do media key events show the HUD | **Could not be verified.** The probe process is not trusted for Accessibility (`accessibility trusted: false`); macOS drops synthetic events from an untrusted process, and there is no HUD in the screenshots. | The media key path for volume/brightness stays in the design (the permission is required anyway). For the keyboard backlight, **Path B (CoreBrightness + own overlay)** is primary; Path A will be tried once the permission is granted. |
| 5 | Quarter step with ⌥⇧ | Could not be verified for the same reason. | Check manually with `docs/testing.md` once the app is installed and the permission is granted. |
| 6 | Cursor freeze | Could not be verified (permission). Review note: a `mouseMoved` swallowed at session level may not stop the cursor. | Tap B was moved to the `.cghidEventTap` location (the event is swallowed before it reaches WindowServer). Added to the manual checklist. |
| 7 | Switcher with ⌘ held + Tab | Could not be verified (permission). | Added to the manual checklist. |
| 8 | Idle memory | `TrrekProbe mem` → phys_footprint 1.6 MB (CLI, no AppKit). | The AppKit menu bar app will be measured with `make perf`; the budget is 15 MB. |

## Threshold updates

The measured fingertip major axis is 8–11.6 mm; `palmMajorAxisMM = 20` remains a reasonable palm threshold. The other thresholds are unchanged.

## Open items

- Closed (2026-11-04, first manual test round, 0.1.0 build signed with `trrek Local Signing`, Accessibility granted):
  - 4: The volume and brightness edges work; the change is visible in the system's own indicator.
  - 5–7: The user confirmed the general gesture set "works in general".
  - 6 (cursor freeze): swallowing the move events in the HID tap did not stop the cursor; when the mouse and cursor are disconnected while freezing (`CGAssociateMouseAndMouseCursorPosition`) and the position is preserved, the cursor stayed in place (confirmed by the user).
- The key event timestamp unit no longer matters: decision 25 uses arrival time.
- Signing note: after switching from an ad-hoc build to a fixed identity, the old Accessibility entry does not match the new signature; reset it with `tccutil reset Accessibility com.burakseyitkara.trrek` and grant the permission once again.
