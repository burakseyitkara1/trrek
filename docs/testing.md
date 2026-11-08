# trrek manual test list

Behavior that needs hardware and system permissions cannot be verified with automated tests; this list is run before every release. Precondition: `make install`, the app is in the menu bar, Accessibility permission is granted (unless stated otherwise). Settings start at their defaults.

## 1. First run

### 1.1 The welcome window appears only on first launch
- **How:** Delete the settings with `defaults delete com.burakseyitkara.trrek`, open the app, quit it, open it again.
- **Expected:** The welcome window appears on first launch and becomes the key window (the title bar looks active, Return triggers "Done"); it does not appear on the second launch when permission is granted.

### 1.2 Windows opened from the menu become the key window
- **How:** Open Settings and Welcome from the menu bar icon.
- **Expected:** The window comes to the front, the title bar looks active, keyboard input goes to the window.

### 1.3 Later launch without permission
- **How:** Remove the Accessibility permission (or reinstall with `make install`), open trrek.
- **Expected:** The welcome window opens again and says "trrek needs Accessibility access to change volume, brightness and the other controls."; the menu bar icon has a dot in its top right corner. The dot disappears once permission is granted.

### 1.3a Welcome animation
- **How:** Delete the settings and open trrek (welcome window); then turn on System Settings › Accessibility › Display › Reduce Motion and repeat.
- **Expected:** With Reduce Motion off the cards appear one after another; with it on they all appear immediately, without animation.

### 1.4 Reopening the app opens the settings
- **How:** While trrek is running, open it again from the Applications folder (`~/Applications/trrek.app`) or with `open ~/Applications/trrek.app`.
- **Expected:** The settings window opens (or comes to the front).

## 2. Edges

On each edge, put one finger on the edge strip and slide along the edge.

### 2.1 Right edge: volume
- **How:** Slide up/down on the right edge.
- **Expected:** The system volume changes step by step and the system's own volume indicator appears; trrek's overlay does not appear.

### 2.2 Left edge: brightness
- **How:** Slide up/down on the left edge.
- **Expected:** The screen brightness changes step by step and the system's own brightness indicator appears; trrek's overlay does not appear.

### 2.2a External monitor brightness (DDC/CI capable monitor)
- **How:** Connect a monitor that supports DDC/CI (DDC/CI must be on in the monitor's own menu). Turn on External Monitor Brightness in the Edges tab. Move the pointer to the external display and slide up/down on the brightness edge; then move the pointer to the built-in display and repeat. Note the output of `swift run TrrekProbe ddc list` (display, matched service, `brightness: <current>/<max>`).
- **Expected:** While the pointer is on the external display, that monitor's brightness changes step by step (fine step with ⌥⇧); trrek's overlay at the top right of the external display shows the new percentage; the slide does not hang and the other edges work without delay. If the brightness is changed with the monitor's own buttons and you slide again a few seconds later, it continues from the new value. While the pointer is on the built-in display, the built-in display's brightness changes with the system indicator. When the setting is off, the media key path is used on the external display too. With several external monitors, each one changes only while the pointer is on it.

### 2.2b External monitor brightness (monitor without DDC/CI support)
- **How:** Connect a wired monitor that does not support DDC/CI (or has DDC/CI turned off in its menu), External Monitor Brightness on; slide on the brightness edge while the pointer is on that display. Note the output of `swift run TrrekProbe ddc list`. Then do a few more slides with `log stream --predicate 'subsystem == "com.burakseyitkara.trrek"'` open.
- **Expected:** The overlay shows "No DDC" without a level bar and without being cut off; trrek does not freeze or crash, the built-in display's brightness does not change. The probe prints an error for that display (`no valid reply` or `I2C write failed …`). The "external brightness step failed" log line appears once on entering the error state, not on every step.

### 2.2c External display, no DDC service (wireless/virtual display)
- **How:** Add a wireless mirror or a virtual display (a display with no DDC service), External Monitor Brightness on; slide on the brightness edge while the pointer is on that display. Note the output of `swift run TrrekProbe ddc list`.
- **Expected:** The probe prints `service: none` for that display. "No DDC" does not appear; the brightness edge uses the media key path (the system indicator; the built-in brightness may change depending on the display).

### 2.2d The overlay follows the pointer's display
- **How:** With two displays (at least one external), set the top edge to Keyboard Backlight; slide while the pointer is on one display, then while the overlay is visible move the pointer to the other display and slide again.
- **Expected:** Each time the overlay appears at the top right of the display where the pointer is; while visible it moves to the other display with the next value.

### 2.3 Top edge: app switching
- **How:** Slide right on the top edge; while sliding, watch the ⌘-Tab app switcher open and the selection advance; lift the finger.
- **Expected:** The app switcher opens, sliding advances the selection, and when the finger lifts the selected app is activated. If a second finger is put down before lifting, the switcher is cancelled and ⌘ does not stay held.

### 2.4 Bottom edge: keyboard backlight
- **How:** Slide right/left on the bottom edge (the bottom edge action is Keyboard Backlight; on a Mac that does not support it the option is disabled).
- **Expected:** The keyboard backlight changes; trrek's overlay shows a level bar and the percentage ("100%" without being cut off) at the top right of the display where the pointer is, and disappears about 1 s after the last step. The behavior at the end of the range is in 2.5.

### 2.5 A single limit haptic at the end of the range (all level edges)
- **How:** Haptic Medium. Raise the volume to the top on the right edge and, without lifting the finger, slide a few more cm in the same direction; then change direction; lift the finger and push to the top again with a new slide. Do the same by lowering the volume to the bottom (without muting), with the built-in display brightness on the left edge (top and bottom), with the keyboard backlight edge, and on a DDC/CI capable external monitor (External Monitor Brightness on, pointer on the external display). Also slide at the bottom while the volume is muted (Mute).
- **Expected:** The step that reaches the limit gives the normal step haptic; the first step pushed beyond the limit gives a single limit haptic, the following ones give no haptic at all and send no key (no feeling that the level is "increasing"; on edges with an overlay, the overlay keeps showing the limit value). When the direction changes, the step haptics come back immediately. Pushing to the limit in a new slide again gives a single limit haptic. On an external monitor the limit haptic comes together with the result of the step that reaches the limit. While the volume is muted the level is unknown, so the old behavior continues (a key and a haptic on every step).

### 2.6 Top/bottom edge: scrub video
- **How:** In the Edges tab set Top Edge to Scrub Video. Open a video in the browser and play it; slide right on the top edge, then slide left.
- **Expected:** About every 6 mm the video skips forward (→) or back (←); the overlay shows an icon and the exact time such as "+15 s" / "−10 s" (no bar; long labels such as "+100 s" are not cut off). When the finger lifts no extra key is sent and the counter is reset. The action is off when the Accessibility permission is missing.

### 2.7 Scrub video while the Hold-to-Slide key is held
- **How:** In Advanced set Hold-to-Slide Key to Shift (Hold); slide on the top edge in the video while Shift is held. Then repeat with Control.
- **Expected:** The video skips with plain arrow key behavior (the same time per step); there is no text selection or Space change.

### 2.8 Scrub video while the trrek window is in front
- **How:** Top Edge Scrub Video; bring trrek's settings window to the front (with a picker focused in the Edges tab) and slide on the top edge.
- **Expected:** No arrow key is sent at all (the picker value or list selection does not change), the overlay does not appear. When another app comes to the front, scrubbing works again.
- **Extra:** Set Top Edge in turn to Switch Tabs, Zoom and Undo & Redo and slide while the settings window is in front: keyboard focus does not move between controls, no setting is undone. Switch Desktops, on the other hand, changes the desktop even while the window is in front.

### 2.9 Media edge: play/pause
- **How:** Set the action of one edge to Media; double tap on that edge. Also try it on the left or right edge.
- **Expected:** The playing media plays/pauses.

### 2.10 Left and right edge pickers
- **How:** Open the Left Edge and Right Edge pickers in the Edges tab; then set Left Edge to Switch Apps and Right Edge to Keyboard Backlight. Slide up on the left edge, then down, lift the finger; once also put a second finger down before lifting. On the right edge raise the keyboard backlight to the top and keep pushing.
- **Expected:** Both pickers show the same list as the four edges (Volume, Brightness, Keyboard Backlight, Switch Apps, Switch Tabs, Switch Desktops, Scrub Video, Media, Zoom, Undo & Redo, Off); there is no Swap Sides switch. The diagram shows the action of all four edges. On the left edge up = next app, down = previous; when lifted the selected app is activated, a second finger cancels the switcher, ⌘ does not stay held. On the right edge the overlay shows the keyboard backlight level and a single limit haptic comes at the limit (as in 2.5).

### 2.11 Switch Tabs
- **How:** Set Top Edge to Switch Tabs; in a browser window with several tabs slide right, then left on the top edge. Then set Right Edge to Switch Tabs and slide up/down.
- **Expected:** One tab about every 12 mm: right on a horizontal edge and up on a vertical edge is the next tab, the opposite direction is the previous tab. Nothing extra happens when the finger lifts.

### 2.12 Switch Desktops
- **How:** Create at least two desktops in Mission Control; in System Settings › Keyboard › Keyboard Shortcuts › Mission Control, "Move left a space" and "Move right a space" must be on. Set Bottom Edge to Switch Desktops; slide right, then left on the bottom edge. Then set Left Edge to Switch Desktops and slide up/down.
- **Expected:** One desktop about every 20 mm: right/up goes to the desktop on the right, left/down goes to the desktop on the left.

### 2.13 Zoom
- **How:** Set Top Edge to Zoom; with a page open in the browser slide right, then left on the top edge.
- **Expected:** About every 8 mm the page zooms in one level (right/up) or zooms out (left/down).

### 2.14 Undo & Redo
- **How:** Make several separate changes in a text editor. Set Top Edge to Undo & Redo; slide left on the top edge, then slide right.
- **Expected:** About every 10 mm one undo (⌘Z) to the left/down, one redo (⇧⌘Z) to the right/up.

### 2.15 Migration of old settings (Swap Sides)
- **How:** Quit trrek (`osascript -e 'quit app "trrek"'`); run `defaults write com.burakseyitkara.trrek settings -data "$(printf '{"schemaVersion":1,"swapSides":true}' | xxd -p | tr -d '\n')"`; open trrek and look at the Edges tab; slide on the right and left edges.
- **Expected:** Left Edge shows Volume, Right Edge shows Brightness; the left edge changes the volume, the right edge changes the brightness. After a setting is changed, the decoded JSON from `defaults read com.burakseyitkara.trrek settings` has no `swapSides`, it has `leftEdge` and `rightEdge`.

### 2.16 Edges per app: adding, editing, removing
- **How:** In the Edges tab open Edges For: it lists All Apps and Add App…. Choose Add App…, pick a browser; also try picking `trrek.app` once. Set Top Edge to Switch Tabs for the browser, leave the other three on Same as All Apps. Switch Edges For back to All Apps and change Right Edge. Close and reopen the window. Do it once in the English and once in the Turkish interface.
- **Expected:** The app chooser is a sheet on the settings window that opens in `/Applications`; trrek is not added. After adding, Edges For shows the browser with its icon and name, each edge picker starts with "Same as All Apps (<action>)", the caption under Edges For says "These edges apply while <app> is in front." and a "Remove <app>" button is on its own row below it (also with a long app name, in both languages); the diagram shows Switch Tabs on top and the All Apps actions on the other edges. The browser's Right Edge follows the All Apps change. Reopening the window starts on All Apps. Remove <app> deletes the browser's edges and returns to All Apps. The tab scrolls and every control is reachable in both languages; the Accessibility note under an edge follows the action that edge runs.

### 2.17 Edges per app: switching with the front app
- **How:** With the browser set to Switch Tabs on the top edge (2.16) and All Apps on Switch Apps, slide on the top edge in the browser, then in another app; open the menu in each. Set a corner to Mute; with tap to click on and the browser in front, double tap that corner while the pointer is over another app's window (the first tap brings that app to the front).
- **Expected:** In the browser the top edge switches tabs and the menu shows "Edges set for <browser>" under the status line; in the other app the top edge opens the app switcher and the menu has no such line. A browser whose edges are all Same as All Apps (or set to the All Apps actions) shows no line either, and neither does any app while the status line says "Accessibility access needed" or "Trackpad not found". The double tap mutes, although the front app changed between the two taps.

### 2.18 Edges per app: a slide in progress is not interrupted
- **How:** Give an app (A) Switch Desktops on the bottom edge, with A on its own desktop and another app on the next desktop; All Apps has the bottom edge on Keyboard Backlight. In A, slide along the bottom edge across two desktops without lifting, then lift and slide on the bottom edge again.
- **Expected:** The slide keeps switching desktops to the end even though the front app changes under the finger; there is no stray commit, haptic or cursor jump. After lifting, the next slide runs the new front app's bottom edge (the keyboard backlight).

### 2.19 Edges per app: trrek window in front, paused apps
- **How:** With the browser in front (2.17), open Settings from the menu and slide on the top edge while the window is in front. Then add the browser to Paused Apps and bring it to the front.
- **Expected:** With the trrek window over the browser the top edge still switches the browser's tabs and the menu still says "Edges set for <browser>". Once the browser is paused, the edges do nothing in it, the status line says "Paused in <browser>" and the "Edges set for" line is gone.

### 2.20 Edges per app: export, import and reset
- **How:** Export the settings (7.4) with two apps that have their own edges; remove both, then import the file. Then press Reset to Defaults….
- **Expected:** The file's `settings` has `appEdgeProfiles` with each app's bundle ID and only the edges it sets. After the import both apps are back in Edges For with the same edges. Reset to Defaults removes every app's edges and the Edges tab shows All Apps.

## 3. Corners

### 3.1 Corner double tap
- **How:** Assign Mute to one corner and Screenshot to another in settings; double tap on each corner.
- **Expected:** Mute turns the sound off/on; Screenshot opens the screenshot interface. A single tap on a corner does nothing.

### 3.1a New corner actions
- **How:** Assign Play/Pause, Mission Control, App Windows, Show Desktop, Spotlight, Lock Screen and Screenshot Area to the corners in turn and double tap on each. Also try the three related to Mission Control with the shortcuts in System Settings › Keyboard › Keyboard Shortcuts › Mission Control turned off.
- **Expected:** Play/Pause plays/pauses the playing media. Mission Control shows all windows, App Windows shows the windows of the front app, Show Desktop shows the desktop (each also works with the shortcuts turned off; double tapping again or Esc closes the view). Spotlight opens the search field. Lock Screen locks the screen. Screenshot Area opens the area selection cursor. If an error occurs trrek does not crash; the "mission control" line appears in the output of `/usr/bin/log show --last 5m --predicate 'subsystem == "com.burakseyitkara.trrek"'`.

### 3.1b A corner whose edge is Off
- **How:** In the Edges tab set Left Edge to Off; in Corners & Taps assign Mission Control to Top Left and double tap on the top left corner. From the same corner slide down (along the left edge) and right (along the top edge). Then set Top Edge to Off as well and repeat the double tap.
- **Expected:** The double tap opens Mission Control in both cases. Sliding down does nothing (the cursor does not freeze, no haptic); sliding right runs the action of the top edge (Switch Apps). Sliding in the middle of the left edge does nothing.

### 3.2 Clicking the corner badge rotates the action
- **How:** Click the badge of a corner in the Corners & Taps tab.
- **Expected:** On each click the action advances in the order in the picker (Off → Mute → Screenshot → Play/Pause → Mission Control → App Windows → Show Desktop → Spotlight → Lock Screen → Screenshot Area → Off); the badge's icon shows the action.

### 3.3 Bottom Quarter Only limits the side edges to the bottom quarter
- **How:** Turn on Bottom Quarter Only in the Edges tab; try sliding in the top half of the right edge, then try in its bottom quarter; double tap on a top corner.
- **Expected:** The side edges respond only in the bottom quarter; corner double taps still work.

## 4. Other gestures

### 4.1 Three-finger tap: middle click
- **How:** Enable it; tap with three fingers on a link.
- **Expected:** A middle click is sent (the link opens in a new tab).

### 4.2 Precision Control fine steps (⌥⇧)
- **How:** Turn on Precision Control from the menu or the General tab; slide on the right edge, then turn it off and slide again.
- **Expected:** When on, each step changes the level by a quarter step (the system treats it as if the volume/brightness key were sent with ⌥⇧); when off, normal steps.

### 4.2a Slide Sensitivity
- **How:** In the General tab set Slide Sensitivity in turn to Very Low, Standard and Very High; for each, slide the same distance (e.g. from the bottom to the middle) on the right edge (Volume) and count the steps. At Very High raise the volume to the top and keep pushing; also try it on a Switch Apps edge.
- **Expected:** The fewest steps at Very Low, the most steps at Very High (about 0.6 and 1.6 times the steps per distance compared with Standard). The distance needed for the slide to start does not change. At Very High too, a single limit haptic comes at the limit, then silence (2.5). The selection is kept when the window is closed and opened.

### 4.3 The cursor freezes during a slide
- **How:** While sliding on an edge, watch whether your finger also moves the cursor.
- **Expected:** The cursor stays in place for the duration of the slide; movement returns when the finger lifts.

### 4.4 Scroll suppression
- **How:** With Freeze Cursor on, slide on the right edge; have a scrollable window open behind. Then turn Freeze Cursor off and repeat.
- **Expected:** With Freeze Cursor on, the window behind does not scroll; when off, scrolling is not suppressed.

## 5. Gates

### 5.1 Typing gate
- **How:** While typing (within a short time after the last key), touch an edge.
- **Expected:** A new gesture does not start; shortly after you stop typing, gestures work.

### 5.2 Palm rejection
- **How:** Touch an edge with the palm.
- **Expected:** The gesture does not start.

### 5.3 Hold mode
- **How:** In the Advanced tab choose a key (e.g. Option) as Hold-to-Slide Key and Hold as Mode; slide on an edge without pressing the key, then while pressing it.
- **Expected:** No gesture when the key is not held; it works while held. In Hold mode there is no Hold-to-Slide row in the menu.

### 5.4 Toggle mode
- **How:** Set Mode to Toggle; open the menu, press the key once, slide; press again.
- **Expected:** Gestures are on after the first press and off after the second. The "Hold-to-Slide: On" / "Hold-to-Slide: Off" row appears in the menu only in Toggle mode (and when a key is selected). Clicking while the key is held (e.g. ⌘-click) or adding another modifier does not change the state.

### 5.5 Pause in app
- **How:** Add an app to the Advanced › Paused Apps list with `+`; slide on an edge while that app is in front; remove it with `−`.
- **Expected:** Gestures do not work while the app in the list is in front, and work once it is removed. `+`/`−` update the list correctly. `+` opens the app picker not as a separate window but as a sheet attached to the settings window; if `trrek.app` is chosen in the picker it is not added to the list.

### 5.5a Pausing is kept while the trrek window is in front
- **How:** Add an app to the Paused Apps list and bring it to the front; open Settings (or Show Welcome, About trrek) from the menu and slide on an edge while the window is in front; look at the menu's status line. Then bring an app that is not in the list to the front and do the same.
- **Expected:** With the trrek window in front on top of the paused app, gestures keep not working and the status line says "Paused in <app>"; on top of an app that is not in the list, gestures work. If the app is removed from the list with `−` while the window is in front, gestures work immediately.

## 6. System events

### 6.1 After sleep
- **How:** Put the Mac to sleep, wake it, slide on an edge.
- **Expected:** Gestures work again; no restart is needed. Hold-to-Slide that was on in Toggle mode stays on after sleep too.

### 6.2 Plugging/unplugging a trackpad
- **How:** Connect an external trackpad, slide on an edge, unplug it, connect it again.
- **Expected:** Gestures work on the external device too; there is no hang or crash while unplugging.

### 6.2a Haptics on an external trackpad
- **How:** Connect an external trackpad to a Mac with a built-in trackpad (Haptic Medium). Slide on the right edge of the external trackpad, then slide on the built-in trackpad; try corner double taps and the limit haptic (2.5) on both surfaces. Then repeat by unplugging and plugging in the external trackpad or by sleeping and waking the Mac.
- **Expected:** The haptic is felt each time on the trackpad where the finger is sliding; when sliding on the external trackpad the built-in trackpad does not vibrate and vice versa. After unplugging/plugging and after sleep, each surface also gives its own haptic.

### 6.3 Accessibility permission revoked / granted
- **How:** Remove trrek's permission in System Settings › Privacy & Security › Accessibility; then grant it again.
- **Expected:** The status line in the menu becomes "Accessibility access needed", the "Grant Accessibility…" item and a dot on the icon appear. Only the keyboard backlight edge works; the other edges, corners, middle click and cursor freeze do not work, and the Edges/Corners diagram shows them as "Off" (the Advanced and General tabs say the permission is required). When permission is granted, gestures come back without restarting the app, the status line becomes "trrek is active", "Grant Accessibility…" and the dot disappear.

### 6.4 Launch at Login
- **How:** Turn it on in General, log out/in; then turn it off and try again. Also, with the settings window closed, turn trrek off in System Settings › Login Items, then open settings.
- **Expected:** When on, the app starts at login, when off it does not; it is consistent with System Settings › Login Items. When the window opens, the Launch at Login switch shows the state in the system.

### 6.5 Trackpad not found → starts by itself when plugged in
- **How:** Open trrek on a Mac without a trackpad (or with the external trackpad unplugged); look at the status line in the menu; then connect an external trackpad.
- **Expected:** First "Trackpad not found" appears; when a trackpad is connected, gestures work without restarting the app and the status line becomes "trrek is active".

### 6.6 Quitting during app switching
- **How:** Run `sleep 3; osascript -e 'quit app "trrek"'` in the terminal; immediately start a Switch Apps slide on the top edge and keep the finger on the trackpad.
- **Expected:** When trrek quits, the app switcher closes; ⌘ does not stay held (later key presses are not treated as ⌘ shortcuts).

### 6.6a Quitting by signal (SIGTERM/SIGINT)
- **How:** Run `sleep 3; pkill -TERM -x trrek` in the terminal; immediately start a Switch Apps slide on the top edge and keep the finger on the trackpad. Repeat with `pkill -INT -x trrek`.
- **Expected:** trrek quits, the app switcher closes, ⌘ does not stay held. The line "signal 15; quitting" (2 for INT) appears in the output of `/usr/bin/log show --last 1m --predicate 'subsystem == "com.burakseyitkara.trrek"'`. Write the command with its full path: zsh's own `log` command shadows the system tool. After trrek opens, wait a few seconds; a SIGTERM that arrives before the signal handler is installed quits the app without writing a log entry.

### 6.7 Mouse with a touch surface connected
- **How:** Connect a mouse with a touch surface; look at the output of `swift run TrrekProbe devices`; slide along the edge on the mouse's surface and double tap on the corners; then slide on the trackpad.
- **Expected:** The mouse is listed as `kind=other` and its touches do nothing; trackpad gestures are not affected. Only when the mouse is connected (without a trackpad) does the status line say "Trackpad not found".

## 7. Settings window

### 7.1 Tabs
- **How:** Go through the General, Edges, Corners & Taps and Advanced tabs; change values.
- **Expected:** Changes take effect immediately and are kept when the window is closed and opened.

### 7.2 Notes on options and disabled ones
- **How:** Open the Left, Right, Top and Bottom Edge pickers in the Edges tab.
- **Expected:** All four pickers show the same list. A note is shown next to the option name: "Scrub Video — Uses ← and → in the front app", "Switch Tabs — Uses ⌃⇥ and ⌃⇧⇥ in the front app", "Switch Desktops — Uses ⌃← and ⌃→", "Zoom — Uses ⌘= and ⌘− in the front app", "Undo & Redo — Uses ⌘Z and ⇧⌘Z in the front app"; all are selectable. On a Mac without a keyboard backlight, "Keyboard Backlight — Not available on this Mac" is disabled in every picker and the selected value is shown as Media.

### 7.2a Edge note requiring Accessibility
- **How:** Remove the Accessibility permission; in the Edges tab set Top Edge to Switch Apps or Scrub Video, Left Edge to Switch Tabs, Zoom or Undo & Redo.
- **Expected:** A "Needs Accessibility access" note appears under the picker's title; it does not appear while Keyboard Backlight is selected. The note disappears when permission is granted.

### 7.2b External Monitor Brightness unavailable
- **How:** Open the Edges tab on a system without the DDC symbols (or in a build where the log shows "external brightness available: false").
- **Expected:** The External Monitor Brightness switch is off and disabled, and "Not available on this Mac" is written under it.

### 7.3 Reset to Defaults
- **How:** Change a few settings; press Reset to Defaults… in the General tab.
- **Expected:** A confirmation alert appears; cancelling changes nothing, confirming returns all settings to the defaults. Launch at Login and Language do not change.

### 7.4 Exporting settings
- **How:** Press Export Settings… in the General tab; also try it while trrek is in the background.
- **Expected:** The save panel is attached to the settings window as a sheet, the suggested name is "trrek Settings.trrek" (in the Turkish interface "trrek Ayarları.trrek"). The saved file is indented JSON; it has the keys `format`, `formatVersion`, `appVersion` and `settings`, and no `launchAtLogin` or `welcomeShown`.

### 7.5 Importing settings
- **How:** After exporting, change a few settings; press Import Settings… and choose the file. Once also Cancel, once Replace.
- **Expected:** The open panel comes as a sheet and only `.trrek` files can be chosen. The "Replace your current settings with the ones in “…”?" confirmation appears; Cancel changes nothing, Replace brings back the exported settings and the edges immediately work with the new settings. Launch at Login and Language do not change.

### 7.6 Importing an invalid file
- **How:** Save an empty file, random text, a file larger than 1 MB, a JSON with a different `"format"` value and a file with `"formatVersion": 2` written in it, each with the `.trrek` extension, and import them in turn.
- **Expected:** The app does not crash; the "“…” could not be imported." alert says why (corrupt/other file or newer version) and the settings do not change.

### 7.7 Double-clicking from Finder
- **How:** Double-click a `.trrek` file in Finder while trrek is running and while it is not; also try it while the settings window is on the Edges tab.
- **Expected:** The file's kind is shown as "trrek Settings"; trrek opens or comes to the front, the settings window opens on the General tab and the same confirmation appears. If the welcome window is needed at launch when it was not running, that appears too, and the confirmation is in the settings window. Double-clicking a second `.trrek` file while the confirmation is open does not change the confirmation (it is ignored); Replace applies the first file.

### 7.8 Turkish interface
- **How:** In the General tab set Language to Turkish. Press Relaunch in the "Relaunch trrek to use the new language." row.
- **Expected:** trrek quits and reopens within a few seconds (a single icon remains in the menu bar, a second instance is not opened). All of the following are in Turkish, no English text remains: the menu (the status line, "Hassas Denetim", "İmleci Dondur", while an app is in front "… İçin Duraklat"/"… İçin Sürdür", "Ayarlar…", "Karşılamayı Göster", when permission is missing "Erişilebilirlik İzni Ver…", "trrek Hakkında", "trrek’ten Çık"); the title of the settings window ("trrek Ayarları") and its four tabs (Genel, Kenarlar, Köşe ve Dokunma, Gelişmiş; all four are visible in the tab bar, the `>>` overflow menu does not appear) with all their pickers, options, notes and captions; the edge names in the diagram; the Reset confirmation; the titles and buttons of the Export/Import panels; the import confirmation and the invalid file alert (7.6); the Paused Apps list and the "+" panel; the welcome window (title, edge cards, permission row, buttons); in the keyboard backlight overlay the percentage in the "%50" format, on an external display the error "DDC yok"; the About window. The key symbols (⌘ ⌃ ⇧ ⇥ ← →) stay the same; the Hold-to-Slide Key picker shows Kontrol and Komut, Shift and Option; the scrub overlay shows "+15 sn". The hint in the Köşe ve Dokunma tab is the same as the names "Araştırma ve veri algılayıcıları" and "Tek Parmakla Kuvvetli Tıklayın" in the Trackpad settings. In Finder the kind of the `.trrek` file is shown as "trrek Ayarları". No text is cut off or overflows (especially the welcome cards and segmented pickers).

### 7.9 Returning the language to the system
- **How:** In the Turkish interface set "Dil" to "Sistem" and press "Yeniden Başlat". Then set Language to English, and this time return it to System without relaunching.
- **Expected:** After reopening, the interface follows the system language (English if the system language is not Turkish). `defaults read com.burakseyitkara.trrek AppleLanguages` says the key does not exist. When the selection returns to the language at launch, the relaunch row disappears. When the system language is Turkish, choosing Turkish while System is selected does not show the relaunch row (the displayed language does not change).

### 7.10 Importing does not change the language
- **How:** Export the settings while Language is English, set Language to Turkish and relaunch, then import the file.
- **Expected:** The confirmation says "Oturum Açıldığında Başlat ve dil ayarları değişmez." (Launch at Login and the language settings do not change); after importing the picker stays Turkish, the relaunch row does not appear. The exported file has no `language` key.

### 7.11 Language selection from Language & Region › Applications
- **How:** While Language in trrek is System, add trrek with "+" in System Settings › General › Language & Region › Applications and choose a language different from the system language (Turkish or English); accept the relaunch the system suggests. Then quit and open trrek once more. Finally remove trrek from the Applications list (or set Language to System in trrek).
- **Expected:** trrek opens in the chosen language; in the General tab Language shows that language, the relaunch row does not appear. `defaults read com.burakseyitkara.trrek AppleLanguages` shows the chosen language (e.g. `tr` or `tr-TR`); on the second launch the language does not change either and the value is not overwritten. When Language in trrek is set to System and relaunched, the key is deleted and the selection in the Applications list returns to the default.

## 8. Tools

### 8.1 TrrekProbe key timing
- **How:** Grant the terminal Accessibility permission; run `swift run TrrekProbe keys 10`, press and click a few keys. Line format: `arrival=<arrival time> event=<the event's own timestamp> keyDown` (`flagsChanged` for a modifier, `mouseDown` for a mouse button).
- **Expected:** `arrival=` is the system uptime in seconds (read inside the tap callback) and is the only value trrek uses. `event=` is printed only out of curiosity; since its clock is not documented, trrek does not rely on it. The `arrival=` values must be in increasing order and of the same magnitude as `uptime`.
- **Extra (frame clock):** When `swift run TrrekProbe pipeline 5` starts, ask for a single touch; the output has the form `clock: frame timestamp X, system uptime Y (difference Z s), uptime including sleep W (difference V s)`. The difference must be a constant offset; the engine learns this offset itself.

### 8.2 TrrekProbe keyboard backlight measurement
- **How:** `swift build && .build/debug/TrrekProbe backlight bench` (on a Mac with a keyboard backlight).
- **Expected:** Prints two lines: read + write from the client (`raw read+write`) and a step from the cache (`step from cache`), each with the min/avg/max of 50 loops. The average of the step from the cache is under 0.1 ms. The last line is `failures=0 restored=<initial> ok` and the keyboard backlight returns to its initial level.

## 9. Performance

### 9.1 Idle budget
- **How:** Quit the running instance; `make perf`.
- **Expected:** CPU at most 1% (usually 0.0), physical footprint under 15 MB.

## 10. Updates

Precondition: `make install`. The check state is kept in trrek's defaults domain (`lastUpdateCheck`, `lastFailedUpdateCheck`, `availableUpdate`); a trrek started with `--assume-version` uses its own separate domain (`com.burakseyitkara.trrek.assumed-version`), so a manual trial does not affect the real schedule. To start that trial over, `defaults delete com.burakseyitkara.trrek.assumed-version`. Log: `/usr/bin/log stream --predicate 'subsystem == "com.burakseyitkara.trrek" AND category == "app"'`. trrek sends no notifications and does not touch the Downloads folder.

Install trials are always done on a **copy**; `~/Applications/trrek.app` does not change. The copy: quit trrek (`osascript -e 'quit app "trrek"'`), `rm -rf /tmp/trrek-install-test && mkdir -p /tmp/trrek-install-test && ditto ~/Applications/trrek.app /tmp/trrek-install-test/trrek.app`, `defaults delete com.burakseyitkara.trrek.assumed-version`, then `open -a /tmp/trrek-install-test/trrek.app --args --assume-version 0.2.0`. A released version (e.g. 0.3.0) may not know this flow; what is tried is that the version in the copy installs it. When done, quit the copy, `rm -rf /tmp/trrek-install-test` and `open ~/Applications/trrek.app`. If the copy's version is greater than the latest released version, the install is refused (10.11); the install trial is done with a copy whose version is equal to or smaller than the latest released version.

### 10.1 Badge and menu row
- **How:** Open the copy as above and wait 15 s; look at the menu bar icon, then open the menu. Look also on a light and a dark menu bar, when the Accessibility permission is missing (dot at the top right) and when the hold key switch is on (dot at the bottom right).
- **Expected:** The log shows "update check assumes version 0.2.0" and about 10 s later "update check: X.Y.Z is available"; no notification arrives, no alert appears. A small filled up arrow appears in the top left corner of the icon; it is clearly separate from the dots and does not overlap them. At the very top of the menu there is a bold "Update Available: trrek X.Y.Z" row with a download icon (Turkish: "Güncelleme Mevcut: trrek X.Y.Z"), with a separator below it. When hovering with the mouse or arrow keys the row is highlighted like a normal menu item; VoiceOver reads the row with its title and the icon as "trrek (update available)" (Turkish: "trrek (güncelleme mevcut)"). In General a "trrek X.Y.Z is available" row appears under Check Now with an Update Now button. If trrek is restarted with the same argument before 24 hours have passed, there is no new request, the badge and row stay.

### 10.2 Live progress in the menu, install and relaunch
- **How:** After 10.1 open the menu and click the "Update Available: trrek X.Y.Z" row; do not close the menu. Once also select the row with the arrow keys and press Return (the menu closes; reopen it).
- **Expected:** The menu stays open; the row becomes "Downloading trrek X.Y.Z…" in place and the progress bar to its right (noticeable on a slow connection) fills; if the menu is closed and reopened the row shows the current progress. Then "Installing trrek X.Y.Z…" (indeterminate bar) appears, trrek quits and within a few seconds reopens from the same folder: `pgrep -lf trrek` shows the copy's path (Launch Services mostly gives the resolved `/private/tmp/trrek-install-test/…` form) without `--assume-version`; `defaults read /tmp/trrek-install-test/trrek.app/Contents/Info.plist CFBundleShortVersionString` gives the new version. No confirmation alert appears, no Finder window opens, Gatekeeper does not ask. `ls ~/Library/Caches/com.burakseyitkara.trrek/Updates` is empty or does not exist; there is no new file in `~/Downloads`; there is no `trrek-update-` in `hdiutil info`; `ls -a /tmp/trrek-install-test` shows only `trrek.app`. Gestures work without the Accessibility permission being requested again. The badge and row disappear in the new version. In the open menu "Check for Updates…" is disabled as soon as the download starts, "Quit trrek" is disabled during "Installing…". Turkish: "trrek X.Y.Z İndiriliyor…", "trrek X.Y.Z Yükleniyor…". Also click the row once right after opening the menu (while the check started by the menu is running): the click is not swallowed, the download starts.

### 10.3 Error row and retry
- **How:** Open the copy; click the row and turn off Wi-Fi while the download is running. Then turn Wi-Fi on and click the row again.
- **Expected:** The row becomes "Update Failed — Try Again" (Turkish: "Güncelleme Başarısız — Yeniden Dene"), no alert appears; the log says "update download failed" with the error's domain and code (e.g. `NSURLErrorDomain -1009`), its detail appears as `<private>`; no partial file is left in the cache folder. Clicking starts over and finishes as in 10.2. In General a "The update failed." row appears with a Try Again button.

### 10.4 Browser when it cannot be installed in place
- **How:** Create the copy, run `chmod a-w /tmp/trrek-install-test`, open the copy and click the row; then `chmod u+w /tmp/trrek-install-test`. Also once mount the disk image in Finder, open trrek from there with `--assume-version 0.2.0` and click the row.
- **Expected:** In the non-writable folder and on the disk image the download does not start at all: the release page opens immediately in the browser, the row becomes "Update in Browser…" (Turkish: "Tarayıcıda Güncelle…"); no alert appears, the disk image is not opened, the copy does not change. Clicking the row again reopens the page. The log says "update install not possible here: notWritable" (or `diskImage`).

### 10.5 Manual check
- **How:** Open the copy without `--assume-version` (up to date); choose "Check for Updates…" from the menu, then General › Check Now. Then open the copy with `--assume-version 0.2.0` and try the same two before the badge appears. Also try with Wi-Fi off.
- **Expected:** When up to date: the "trrek is up to date / trrek X.Y.Z is the latest version." alert (modal from the menu, a sheet on the settings window from Check Now). If the check fails, the "Couldn’t check for updates" alert. When a new version is found there is no alert: the badge and menu row appear, in General the "trrek X.Y.Z is available" row appears with Update Now; Update Now starts the flow in the menu and the row also shows progress in General. While a check or update is running Check for Updates… and Check Now are disabled.

### 10.6 Automatic check off
- **How:** Turn off "Check for Updates Automatically" in General; delete the `lastUpdateCheck` key, restart trrek, open the menu a few times, sleep and wake the Mac.
- **Expected:** No "update check" line appears in the log (no request is sent). "Check for Updates…" and Check Now still work. The setting is written to the `.trrek` file as `checkForUpdatesAutomatically`; Reset to Defaults turns it on again.

### 10.7 When the relaunch cannot be started
- **How:** Checked only from the log and with the unit test (`UpdateInstallFlowTests.aFailedRelaunchOffersToRelaunch`); triggering it by hand is not practical.
- **Expected:** The row becomes "Relaunch to Finish Updating" (Turkish: "Güncellemeyi Bitirmek İçin Yeniden Başlat"); clicking retries the relaunch.

### 10.8 A modified update is rejected
- **How:** Covered by the unit and real DMG tests (10.10); since the app downloads only from the fixed release address, a modified DMG cannot be supplied from the UI.
- **Expected:** An unsigned or re-signed update is not installed; the row becomes "Update Failed — Try Again".

### 10.9 Cleanup of an interrupted update
- **How:** In the copy click the row and quit with `osascript -e 'quit app "trrek"'` during "Installing…" (or create a file named `~/Library/Caches/com.burakseyitkara.trrek/Updates/trrek-v9.9.9.dmg` and an empty `$TMPDIR/trrek-update-x` folder); reopen the copy.
- **Expected:** At launch the cache folder is deleted; no `trrek-update-` mount point in `hdiutil info`, no `trrek-update-*` folder in `$TMPDIR`, no `.trrek-previous` next to the copy.

### 10.10 The real verifier and binder (automatic)
- **How:** Download the released DMG into a temporary folder (`curl -L -o /tmp/trrek-dmg/trrek-v0.3.0.dmg https://github.com/burakseyitkara1/trrek-releases/releases/download/v0.3.0/trrek-v0.3.0.dmg`), produce a Developer ID signed but not notarized `dist/trrek.app` with `make app`; `TRREK_UPDATE_DMG=/tmp/trrek-dmg/trrek-v0.3.0.dmg TRREK_UNNOTARIZED_APP=$PWD/dist/trrek.app make test`.
- **Expected:** `UpdateInstallReleaseTests` passes (~15 s): the image is mounted hidden, copied and ejected, the version is verified; a copy re-signed after being prepared is rejected right before installation and the installed copy does not change; an unsigned DMG is rejected without being mounted; an ad-hoc re-signed copy and a copy with a modified `Info.plist` version are rejected at the signature check, `dist/trrek.app` only at the notarization check ("not notarized app: Optional(…notNotarized)"); a fake installed app in a temporary folder is replaced with the new version, no quarantine or backup remains. If the environment variable is missing the test is skipped. After that there is no `trrek-update-` in `hdiutil info`; `rm -rf /tmp/trrek-dmg`.

### 10.11 An older version is not installed
- **How:** Temporarily set the version to `9.0.0` in `Sources/TrrekEngine/Version.swift` and produce a copy greater than the latest released version with `make app` (what is compared is the compiled `TrrekVersion`; `Info.plist` alone is not enough), copy it with `ditto dist/trrek.app /tmp/trrek-install-test/trrek.app` (the copy steps above), open it with `open -a /tmp/trrek-install-test/trrek.app --args --assume-version 0.2.0` and click the "Update Available" row. When done, `git checkout Sources/TrrekEngine/Version.swift` and produce `dist/trrek.app` again with `make app`.
- **Expected:** The download finishes, the row becomes "Update Failed — Try Again", the browser does not open; the log shows "update X.Y.Z is older than 9.0.0"; `defaults read /tmp/trrek-install-test/trrek.app/Contents/Info.plist CFBundleShortVersionString` still gives `9.0.0`; no DMG is left in the cache folder.
