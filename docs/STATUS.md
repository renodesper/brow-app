# Brow: features, progress and what's next

Last updated 27 Nov 2026: version 1.0.0 (v0.2.0 plus the v2 native macOS look, several displays, interactive swipe and the release tooling), compiled and tested. Released as a plain, ad-hoc signed disk image; notarization waits for an Apple Developer account.

## Where the project stands

All four features are written. **It now builds and runs:** on 26 Nov 2026, with Xcode 27.2 (macOS 27 SDK), `swift build`
and `make run` succeed and all 68 unit tests pass. The only compiler error was a name clash between
`BrowCore.Widget` and `SwiftUI.Widget`, fixed by qualifying the name. Idle, the running app used about 0% CPU and
42 MB (one reading, nothing running). How the island looks was checked on a notch through screenshots; how it
behaves in real use is mostly unchecked.

The full Xcode app is needed, not only the Command Line Tools: SwiftUI's `@State` is a macro whose plugin ships
with Xcode, and without it `SettingsWindow.swift` does not compile.

Each feature below is marked on four steps:

| Step | Meaning |
|---|---|
| Written | The code exists |
| Unit tested | Its logic has tests in `Tests/BrowCoreTests` (all 68 pass) |
| Builds | It has compiled on a Mac |
| Checked by hand | Someone has used it on a MacBook with a notch |

| Feature | Written | Unit tested | Builds | Checked by hand |
|---|---|---|---|---|
| The island (window, hover, open and close) | Yes | No | Yes | No |
| Pomodoro | Yes | Yes | Yes | No |
| Keep Awake | Yes | No | Yes | No |
| AI usage: Codex | Yes | Yes | Yes | No |
| AI usage: Claude Code | Yes | Yes | Yes | No |
| Calendar: list of next events | Yes | No | Yes | No |
| Calendar: event beside the notch | Yes | Yes (timing only) | Yes | No |
| Settings menu, open at login | Yes | No | Yes | No |

Size: about 3,440 lines of code in 17 files (2,780 in the app, 660 in `BrowCore`), about 410 lines of tests
(41 test cases).

## 27 Nov 2026: hiding over full-screen apps

Settings → General → "Show over full-screen apps": **Never** (default), **Only for alerts**, **Always**. Written,
compiled, and covered by unit tests of the decision and the detection (`BrowCore/FullScreenVisibility.swift`); 87 tests
pass in all. Partly checked by hand, see below.

### What it does

On a Space change, when another app is activated, or when the panel's own occlusion changes (and ten more times over
the next 2 s, since the window list can lag the notification), each island asks `CGWindowListCopyWindowInfo` for the
on-screen windows and checks whether another app has one that fills its display. Nothing polls and no private API is
used. Only windows below the menu bar's layer (24) count, so overlays do not.

- A full-screen app on a notched display fills the area below the notch (Y=44, height 1286 on a 2048 x 1330 display
  with a 43.5 pt inset), not the whole display, so both shapes count. A maximised window sat at Y=45, which is why the
  tolerance is 0.75 pt.
- When a full-screen app is seen, the island stays for 0.3 s, then shrinks up into the top of the screen over 0.25 s
  and its drawing goes (`IslandState.isTucked`, in `IslandView`). It grows back out over 0.35 s when the full-screen
  app is gone. The answer must stay "hide" for the whole 0.3 s, so a stale reading of the window list cannot make it
  blink. Reduce Motion uses a short fade. The panel stays ordered in on every Space and lets clicks through while the
  island is tucked.
- `.fullScreenAuxiliary` is on only in Always mode, and in Only for alerts while a peek is showing (the panel is
  ordered out and in when that changes).
- The look follows a reference clip of another notch app: its pill stays through the Space slide, shrinks to a dot and
  grows back. Brow's version shrinks toward the top edge instead of to a dot. The owner judged the result smooth.

### The issue

Nothing public tells an app that a Space swipe, or a full-screen toggle, has started. The Space-change event arrives
when the transition has ended, and entering full screen from the same app sends no app-activation at all. So the
island is on screen for the length of the animation, about 0.5 s, and can only react after it. The detection hides it
within about 10 ms of the event; the hold and the shrink make that read as intended and not as a blink.

### What we tried

| Try | Result |
|---|---|
| Remove `.fullScreenAuxiliary`, keep `.canJoinAllSpaces` | The island stayed visible over a full-screen Safari (seen with Ctrl+Cmd+F). The first test may have been on a maximised window: the green button fills the screen on this macOS and does not enter full screen. |
| `.moveToActiveSpace` without `.canJoinAllSpaces`, `activeSpaceDidChangeNotification` to bring it onto each desktop Space | Still visible in full screen (first test unreliable; repeated in real full screen with detection off: always visible, and on desktops it only showed after the swipe settled). |
| Window level `.mainMenu` | Still visible in full screen, and the island dropped behind the menu bar. Back to `.statusBar`. |
| `NSApplication.currentSystemPresentationOptions` with KVO | Never changed (always 0) for an accessory app. Not usable. |
| A global `NSEvent` monitor for gestures and scrolls, to catch a swipe start | Received nothing during 3-finger Space swipes. |
| Window-list check, exact display size | Never matched: a full-screen app on a notched display is 44 pt shorter. Fixed with the below-the-notch shape. |
| A single re-check after the Space event, then a few at 0.3 to 4 s | The list lags the event; a short burst of ten re-checks over 2 s works. |
| Hiding with `orderOut`, showing with `orderFrontRegardless` | Ordering the panel in during a Space change is silently lost, so the island stayed missing after leaving full screen. The panel now stays ordered in. |
| Hiding with `alphaValue` and `NSAnimationContext` | The fade never showed in a recording: a hard cut. Replaced with the island's own shrink. |
| Counting any display-sized window | The screen recorder's overlays (`screencapture` at layer 1498, `Screenshot` at layer 24) and an overlay of the Claude app (layer 1000) covered the displays and hid the island while recording. Only layers below 24 count now. |

Measured along the way: `activeSpaceDidChangeNotification` reaches Brow (it did not reach a standalone script), the
panel's occlusion change sometimes arrives before the app-activation, and the window list can show full screen up to a
few seconds before Safari's activation event arrives.

### What we have not tried

- **The private SkyLight Space API** (`SLSSpaceGetType`, as other notch apps use). Excluded by "no private APIs"
  (ADR-002); it could give the exact Space type and possibly an earlier signal. Needs the owner's say.
- **The Accessibility API** (`AXFullScreen` on the front window). Exact, but needs the Accessibility permission, which
  Brow does not ask for.
- **A key or event tap** for Ctrl+Cmd+F and the green button, to hide before the transition. Needs Input Monitoring
  and would only cover those two ways in, not a swipe.
- **Comparing `NSScreen.visibleFrame` with `frame`** to tell a hidden menu bar. A heuristic that also fires for an
  auto-hiding menu bar; not tried.
- Other collection behaviors (`.transient`, `.fullScreenNone`, `.fullScreenDisallowsTiling`) and other window levels
  than `.mainMenu`. Not expected to help, since the panel is on every Space on purpose.

### Checked by hand

Built-in notched display, Never: Safari in full screen (Ctrl+Cmd+F) hides the island, and swiping from it to a desktop
Space brings it back with no relaunch. The shrink and grow-back were compared with the reference clip by screen
recordings and judged smooth.

Not checked: the screen recorder no longer hiding the island (fixed after it was seen, not re-tested), several
desktop Spaces, full screen on the external display, a Keynote slideshow (its window layer is not known; the rule is
layers 0 to 23), a maximised or tiled window keeping the island, Only for alerts showing a peek over full screen (and
whether a changed collection behavior needs the order-out and order-in the code does), Always, Stage Manager, and
several apps in full screen at once.

### Known limits

- The island is on screen for the length of the Space animation when full screen is entered or re-entered.
- On a notched display a maximised window and a full-screen one differ by about 1 pt of position. A window manager
  that fills exactly the area below the menu bar (Rectangle's Maximize, say) may be taken for full screen.
- Any other overlay below layer 24 that fills a display would count.

## 26 Nov 2026: v2, the native macOS look

Brow now looks like a Mac app and follows light and dark mode (the design is kept outside this
repository). Built in six pull requests, in this order. `make test` passes (68 tests) and `make app` builds;
none of it has been looked at on a notched MacBook yet.

| Step | What changed |
|---|---|
| 1. Settings is native (#19) | `NavigationSplitView` sidebar with coloured icon tiles, grouped `Form` per pane, native switches, pop-ups, sliders, steppers and checkboxes. No forced appearance or tint. `SettingsKit.swift` is gone |
| 2. Settings content (#20) | Hover-to-open is off by default (a saved choice is kept); island size is segmented Match Notch / Custom; no calendar access button once allowed; AI Usage shows a green dot and "Updated hh:mm"; Keep Awake has a "Keep the display on" switch and "Turn off on low battery" with a "Below" pop-up |
| 3. System font (#25) | Inter, Manrope, `Typeface.swift`, `Support/Fonts`, `ATSApplicationFontsPath` and the Makefile copy step are removed; numbers use `.monospacedDigit()` |
| 4. Island palette and cards (#25) | System dark colours (orange, green, cyan, purple, red, blue), cards #1C1C1E radius 16, sentence-case coloured titles, 32 pt round tinted buttons, 28 pt capsules, title-case peek buttons. The island stays black |
| 5. Right-click menu (#25) | The Keep Awake submenu lists all nine lengths and Indefinitely |
| 6. Header (#25) | The open island shows the date only; the battery label and the read on every open are removed. Keep Awake's battery cut-off is unchanged |

Multiple displays: there is one island on each connected display (the built-in one with its notch, an external one as a black pill at the top centre), turned on for all by default. Settings → General → "Show on displays" turns each off; the last one stays on. The displays share every model (timers, events, usage, settings, the list of screens), but each keeps its own open state, peek, swipe and current screen, so pointing at one display opens only that island; peeks (event starting, Focus done, hello) show on all of them. Tried on a MacBook with an external monitor: the island opens on the external display while the built-in one stays closed, hiding and showing an external display from Settings takes effect at once. A display without a notch (an external monitor, or a Mac with no notch) keeps a plain black pill, drawn like the notch itself (no rim), at the top centre while nothing runs, so there is something to point at; Settings → General → Show on displays → "Always show on displays without a notch" turns it off (on by default). Seen on the Dell with the option on and off. Unplugging the external display while its island was open, then plugging it back in, also worked: the app kept running, its panel went away, the built-in island kept working, and the island came back on the external display on its own. Not tried: three displays.

Afterwards: the Keep Awake default length setting is removed (its only visible effect was an outline on one button, which looked inconsistent); the island's card keeps 30m, 1h, 2h and No end and the right-click menu lists all nine lengths. Settings polish: Calendar access is a switch (off takes you to System Settings, since only it can revoke access); AI Usage no longer shows the green dot and "Updated hh:mm"; notes under sections are left-aligned; the Pomodoro steppers sit to the right of their values.

Releases are disk images now: `make dmg` (plain, ad-hoc, works today) and `make release` (Developer ID, notarized, stapled), published by the Release workflow when a GitHub release is made. The workflow switches to the notarized path by itself once six repository secrets exist (listed in `docs/RELEASING.md`). `make dmg` was run and the image checked by mounting it; the workflow has not run on GitHub yet. A draft Homebrew cask is in `docs/homebrew/brow.rb`, with the steps in `docs/RELEASING.md` (it needs a notarized release and a public, licensed repo first; the repo is private today). Release tooling is in place but unrun: `make hardened` signs like a release with your everyday identity (checked: it runs, Calendar events show), `make release` signs with a Developer ID, notarizes and staples, and `docs/RELEASING.md` has the one-time setup. It needs an Apple Developer account, which the Mac this was built on does not have yet (it only has an Apple Development certificate). The screens now slide as a strip that follows the fingers (the neighbouring screen is visible while swiping), the page dots' pill slides, and a tap is felt on the trackpad when a swipe has gone far enough. The Calendar card with three events was 6 pt taller than its row; its event list is tighter now. Both small leftovers from the v2 spec are now done: the big card numbers have −0.5 tracking, and the calendar glyph beside the notch is a bare symbol in the event's calendar colour (the peek keeps its tile). To check on a Mac, in both light and dark: every Settings pane, the Screens thumbnails, the calendar checkboxes and the island cards and peeks.

Everything below describes v0.2.0 as it was built; where it mentions Inter and Manrope, `SettingsKit.swift`, the
amber / pale blue / teal palette, the battery in the header or the four-length menu, v2 has replaced it.

## 26 Nov 2026: the design, implemented

The UI was redesigned on a Claude Design canvas and then written into the code. It was written on a Linux
machine with no Swift for macOS, and first compiled later the same day (see above). What changed:

| Change | Where |
|---|---|
| The island's top corners flare outward over the menu bar (5 pt closed, 6 pt peeking, 8 pt open) | `IslandShape` in `IslandView.swift`, sizes in `IslandLayout` |
| The design's colors: amber Pomodoro, pale blue Keep Awake, teal Calendar, cards on #161616 | `Palette` in `IslandView.swift`, `Cards.swift` |
| Beside the notch: a pomodoro ring, the event's calendar color, the cup; wings widen for several glyphs; the right side shows an event first, then the pomodoro, then Keep Awake's time left | `CompactIsland` |
| Screens: the open island shows one screen at a time; two-finger swipe or the dots move between them; one, two or four cards per screen; the calendar alone gets a wide card with today's date | `IslandScreens.swift` (tested), `OpenIsland`, `ScreenView`, `CalendarWideCard` |
| Peeks: an event starting and a phase ending show a short banner instead of the whole island; "Focus done" has Start break and Skip break | `PeekView`, `IslandController.showPeek` |
| No menu bar icon: right-click the island for Keep Awake, Pomodoro, Settings… and Quit | `IslandMenu.swift`, the right-click monitor in `IslandController` |
| ⌃⌥⌘, opens Settings from any app, registered with Carbon's `RegisterEventHotKey` (public, no permission, nothing running while idle); skipped, and left out of the Settings text, if another app has it | `GlobalShortcut.swift`, `BrowApp.swift` |
| A Settings window with six panes: General, Screens, Calendar, Pomodoro, Keep Awake, AI Usage | `SettingsWindow.swift` |
| New settings: open on hover or only on click; a master switch and per-feature switches for beside the notch; event lead 5/10/15/30 min; which calendars; all-day events; rounds until a long break; start breaks and focus automatically, separately; end sound; Keep Awake default length, Mac-only mode, battery cut-off at 10/20/30%; Codex on or off; amber from 80%; reset times | the models, `Preferences.swift` |

Things to check first on a Mac, beyond compiling:

- Right-click and two-finger swipes reach the island while another app is active (they use local event monitors on
  a non-activating panel).
- The right-click menu opens and its items work while the app is not active.
- The island's frame grows before and shrinks after each change of size without clipping (it now follows one
  observed size instead of an open/closed flag).
- The Settings window comes to the front from the right-click menu, though the app has no Dock icon.
- The battery cut-off turns Keep Awake off when unplugged below the level.

Closed later the same day (PR #2): Inter and Manrope are bundled in `Support/Fonts` and used for text and numbers
(`Typeface.swift`); the event peek is 448 pt and "Focus done" 512 pt wide; the open header shows the battery
percentage, read when the island opens, instead of the screen name; Settings has the canvas's light look
(`SettingsKit.swift`: pill sidebar, bordered selects and number fields, pill choices, tiles, switches); screens
reorder by dragging their thumbnails, with Move Left and Move Right kept in the right-click menu and as
accessibility actions. PR #2 also gives the spring 20 pt of room to overshoot and makes every change of size follow
one spring.

Added afterwards: a hover delay (0.2 to 2 s, default 0.5 s, a slider in General) and the intermediate state the design
draws: the closed island grows by 8 pt wide and 2 pt tall while the pointer rests on it, which also shows it can be
clicked in click mode. The default used to be a fixed 120 ms.

Keep Awake's default length now offers the design's nine choices (5, 10, 15 and 30 minutes, 1, 2, 3 and 5 hours,
indefinitely). The island's card and right-click menu keep their four usual lengths and add the default when it is
another one, so the default is always there to pick (it is no longer outlined: all buttons look the same until one is on).

A custom island size: General has "Match the notch" (the default) and "Custom size", with width and height sliders from
the notch's own size up by 135 pt and 12 pt (never smaller than the notch). Widths are kept even so the island stays
centred. Reset to notch size puts both back.

Settings > Calendar groups the calendars by account, as the design draws it: each account has an icon, its name, how
many of its calendars are shown, and a fold toggle, and the header says "N of M calendars shown, from K accounts".
Subscribed and birthday calendars start folded. Accounts come from EventKit's `source`, which gives a name and a
type, not an email address, so an account shows its name and kind. Not seen with real calendars: Calendar access has not
been granted to the app on the Mac this was built on, so the grouping was checked with made-up data.

Every control the design draws is now built.

Brow has no Dock or menu bar icon, so launching used to show nothing. It now opens the island for about 2.5 s with "Brow
is running" and a hint on how to open it. Settings > General > Startup has a switch to turn that off.

Seen on a notched MacBook through screenshots on 26 Nov 2026: the open island with the new fonts and header, and the
General, Screens, Calendar, Pomodoro, Keep Awake and AI Usage panes. Still unchecked: real clicks in Settings, drag
and drop of screens, the peeks, swiping between screens, and the overshoot headroom by eye.

Motion work after that, from `UI_MOTION.md` (PRs #4 to #7): Reduce Motion (a short fade replaces the spring, screens
cross-fade); a 280 ms grace before the island closes; content that arrives after the shape and leaves before it
shrinks; press and hover feedback on buttons, a play/pause symbol swap and glyph transitions beside the notch.
Rolling digits on the countdowns were tried and removed: they raised CPU from under 1% to 15–37% while a pomodoro
ran. Scripted clicks on the island work (Start was pressed); hover brightening and the glyph transitions have not been
seen in motion.

## Features

### The island

A black shape over the notch. Hovering opens it into four cards; moving away closes it. While something is going
on, it grows a little to each side of the notch: glyphs on the left, one time on the right.

- One window, whose frame is always the island's own frame, so it never takes a click meant for another app.
- The pointer is noticed by a tracking area; nothing polls for it.
- On a screen without a notch, it sits at the top center and hides while it has nothing to show.
- Code: `IslandController.swift`, `IslandView.swift`, sizes in `AppModel.swift` (`IslandLayout`).

Progress: written. This is the part most likely to need work on a real Mac, see [Known risks](#known-risks).

### Pomodoro

Focus, short break, and a long break after every fourth finished focus round. Start, pause, skip, start over.
Defaults are 25, 5 and 15 minutes; the menu offers other lengths and whether the next phase starts by itself.

- The phase glyph and the time left show beside the notch while it runs.
- When a phase ends, a sound plays and the island opens for a few seconds.
- The cycle is a plain value (`Pomodoro` in `BrowCore`) that is handed the time rather than reading the clock.
  A running phase is stored as its end date, so it stays right across sleep.
- One sleeping task waits for the end of the phase. The display redraws once a second, only while on screen.
- Code: `BrowCore/Pomodoro.swift`, `PomodoroModel.swift`, `PomodoroCard` in `Cards.swift`.

Progress: written, 15 unit tests. A running, paused or waiting phase is saved and carries on after a relaunch; one
that ended while the app was closed is finished quietly (no sound, no peek) and waits to be started. Not built: daily
counts or history, custom lengths beyond the menu's presets.

### Keep Awake

Keeps the display on, and with it the Mac awake, for 30 minutes, 1 hour, 2 hours or until turned off. A cup shows
beside the notch while it is on, with the time it ends.

- One power assertion from macOS; nothing else runs while it is on. macOS drops it if the app quits.
- Code: `KeepAwake.swift`, `KeepAwakeCard` in `Cards.swift`.

Progress: written, no tests (it is a thin wrapper around one system call). A timed run is saved and turns itself back on for what is left after a relaunch; one without an end
is not resumed. Since v0.2.0 the battery cut-off, the Mac-only mode and a default length are in Settings.

### AI usage

How much of each limit is used and when it starts over, for Claude Code and Codex. Read when the island opens;
no login token is read and no network request is made.

- **Codex:** the end of the newest session log under `~/.codex/sessions`. Nothing to set up.
- **Claude Code:** needs "Show Claude Code Usage" turned on in the menu. That rewrites the status-line command in
  `~/.claude/settings.json` to `tee <file> | ( your own command )`, keeps the original file as
  `settings.json.brow-backup`, and puts your command back when turned off.
- A window that has started over since it was read shows as empty rather than as its old number.
- Code: `BrowCore/Usage.swift`, `BrowCore/StatusLineHook.swift`, `UsageModel.swift`, `UsageCard` in `Cards.swift`.

Progress: written, 14 unit tests (parsing, finding the newest log, and the settings edit with its undo). The
`tee` command itself was run in a shell and passes input through unchanged, also when its folder is missing.
Not built: warnings as a limit nears, other tools (Antigravity, Cursor, Copilot), token or cost figures, showing
how old a reading is.

### Calendar

The next three timed events today and tomorrow, from the calendars macOS already has (iCloud, Google, Exchange).

- An event shows beside the notch from 15 minutes before it starts ("in 12m", then "Now"), the island opens for
  a moment as it starts, and it leaves 5 minutes later or when it ends. Can be turned off in the menu.
- Events are read when the island opens, a calendar changes, the day changes or the Mac wakes. One sleeping task
  waits for the next moment an event should appear, start or leave (`Agenda.nextChange`).
- Code: `BrowCore/Agenda.swift`, `CalendarModel.swift`, `CalendarCard` in `Cards.swift`.

Progress: written, 7 unit tests for the timing and 11 for finding meeting links. Reading events through EventKit is
untested. A Join button shows on an event whose URL, location or notes hold a Zoom, Google Meet, Microsoft Teams or
Webex link, from 10 minutes before the start until the end, on the calendar rows and the event peek. Not built:
"time to leave", reminders. Since v0.2.0 all-day events, the choice of calendars and
the lead time (5/10/15/30 min) are in Settings.

### Settings

A Settings window with six panes, opened from the right-click menu or by opening the app again. The right-click
menu itself holds only Keep Awake, Pomodoro, Settings… and Quit.

## Not yet implemented

Ordered roughly by how useful each seems.

| Feature | Notes |
|---|---|
| Usage warnings at 80% and 95% | Needs readings while the island is closed, so a file watcher or a socket: the cost is some idle work |
| Time to leave | Needs location permission and a route lookup over the network |
| More AI tools | Antigravity reports usage through its `agy` command; others vary |
| App icon, signing, notarization | The app is ad-hoc signed; see the README on the Calendar permission |
| Other notch-app staples | Now Playing, volume and brightness HUDs, battery, file shelf: all out of scope so far |

## Known risks

Places where the code is most likely to be wrong, to check first on a Mac.

1. **Hover.** The window resizes under the pointer as the island opens. A missed "pointer left" event would leave
   the island open until the pointer passes over it again.
2. **Opening animation.** The window grows before the island animates and shrinks after. If the two get out of
   step, the island will look clipped or jump.
3. **Clicks.** The window never becomes the active window, by design. Buttons should still respond to the first
   click, but this is unconfirmed.
4. **Card layout.** Sizes are fixed numbers chosen without seeing them. Four usage rows, or a 12-hour clock, may
   not fit.
5. **Sound during sleep.** A pomodoro phase that ends while the lid is closed may play its sound into a sleeping
   Mac instead of waiting for it to wake.
6. **File formats.** The Claude Code and Codex formats are read as other tools document them, not as checked
   against real files on this Mac. A change in either shows as "no limits found", not as wrong numbers.
7. **`settings.json` key order.** Turning Claude Code usage on rewrites the file with keys sorted alphabetically.
   Content is kept; order and spacing are not.

## What we can improve

**Before anything else**

- Put the folder under git (it has no commits yet), so changes from here on can be undone.
- Go through the risks above on a real notch.

**Quality**

- Tests for the app layer: `PomodoroModel` and `CalendarModel` could take a clock and a fake event source, the
  way `BrowCore` already takes the time.
- Accessibility labels on the icon-only buttons, and VoiceOver in general.
- Localizable text. Everything is English and hard-coded.

**Behaviour**

- ~~Follow the screen the pointer is on, not only the built-in one.~~ Done: one island per display (see below).
- Show how old a usage reading is ("as of 14:02"); numbers are only as fresh as the tool's last reply.
- Write the Claude Code capture file in one step, so a read can never land on a half-written file. Today a
  half-written file is simply ignored until the next open.
- On a screen without a notch, the hidden island still takes clicks in a 180 pt strip of the menu bar.

**Efficiency**

- Measure before changing anything: memory and CPU, idle and with a pomodoro running. The design aims for no work
  while idle, but that is a claim until measured.
- The once-a-second countdown is the only steady cost. It could tick once a minute beside the notch and once a
  second only in the open island.

## Related notes

- [`../README.md`](../README.md): building, running, and where the code is.
