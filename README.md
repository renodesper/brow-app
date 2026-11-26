# Brow

A small app that lives in the MacBook notch. Hover over the notch (or click it, if you prefer) and it opens into
one screen of cards; swipe left or right with two fingers to see the others. Four features:

- **Pomodoro**: focus, short break, and a long break after every few focus rounds. Start, pause, skip, start over.
  A ring and the time left rest beside the notch while it runs, and the island opens a little when a phase ends,
  with Start break and Skip break.
- **Keep Awake**: keeps the Mac awake, and the display on unless you choose otherwise, for 30 minutes, 1 hour,
  2 hours, or until you turn it off. It can turn itself off when the battery runs low.
- **AI Usage**: how much of your Claude Code and Codex limits you've used and when they start over.
- **Calendar**: your next events today and tomorrow, from the calendars macOS already knows. An event shows beside
  the notch from 15 minutes before it starts ("in 12m", then "Now"), and the island opens for a moment as it starts.
  A Join button appears on events with a Zoom, Google Meet, Microsoft Teams or Webex link.

**Right-click the island** for Keep Awake, Pomodoro, Settings and Quit. There is no Dock icon and no menu bar icon.
Opening the app again from Finder also shows Settings, and so does **⌃⌥⌘,** (Control-Option-Command-Comma) from any app,
which needs no permission. If another app already holds that combination, Brow has no shortcut and the Settings text
doesn't mention one.

**Settings** has a pane for each part: General, Screens, Calendar, Pomodoro, Keep Awake and AI Usage. Under
Screens you choose how many screens the open island has (up to five) and which cards each one shows: one card
across, two side by side, or four in a grid.

The design is on a Claude Design canvas: closed states, the open island, peeks, the right-click menu, swiping
between screens, and the six Settings panes.

## Build and run

Needs macOS 14 or later and Xcode 15 or later (for `swift build`). No other tools.

```sh
make test      # unit tests for the logic
make run       # build, bundle into build/Brow.app, and open it
make install   # copy the app to /Applications
```

> **Status:** it builds and all 41 tests pass (Xcode 27.2; the Command Line Tools alone are not enough, because
> SwiftUI's `@State` macro plugin ships with Xcode). Behavior on a real notch is still being checked.

macOS ties the Calendar permission to the app's signature. The default ad-hoc signature changes with every
build, so the permission is asked again after each rebuild. To keep it, sign with your own identity:

```sh
security find-identity -v -p codesigning
make run SIGN_ID="Apple Development: you@example.com (TEAMID)"
```

To keep the identity out of your commands, put `SIGN_ID := …` once in `Makefile.local` (not committed). A disk image
is `make dmg`; one that other people can open without a warning, signed with a Developer ID and notarized, is
`make release`. Publishing a release on GitHub builds and attaches the image by itself; see `docs/RELEASING.md`.

## Installing a release

Download `Brow-<version>.dmg` from the releases page, open it and drag Brow onto Applications. Until releases are
notarized, macOS warns that the developer cannot be verified: open Brow once, then System Settings → Privacy &
Security → "Open Anyway". Calendar access is asked again after each update for the same reason.

## Removing Brow

Deleting the app is enough, and it does not break anything. If you turned on AI Usage for Claude Code, a small
wrapper stays in the `statusLine` of `~/.claude/settings.json`: Claude Code's status line keeps working as before, since
the wrapper does not need Brow. It only keeps writing a small file into `~/Library/Application Support/Brow` while that
folder exists. To remove both, turn AI Usage for Claude Code off in Brow's Settings **before** deleting the app: your
own status line is put back exactly as it was (a backup sits beside the file as `settings.json.brow-backup`).

## How it stays small and quiet

- **Nothing polls.** The pointer is noticed by a tracking area. Usage files are read when the island opens. A
  running pomodoro holds one sleeping task until its phase ends; the countdown redraws once a second, and only
  while it is on screen. The calendar holds one sleeping task until the next event should appear, start or leave,
  and reads events again only when a calendar changes, the day changes or the Mac wakes.
- **Idle means idle.** With nothing running and no event near, the app has no repeating timers, no file watchers
  and no sockets.
- **One window.** Its frame is the island's own frame, so it never takes a click meant for something else.
- **Lazy.** The calendar store is created the first time it is needed: at launch once you have allowed access
  and events show beside the notch, otherwise never. Turn that off under Settings → Calendar to save its few megabytes.
- **No private APIs, no network, no login tokens.**

## Where things are

```
Sources/BrowCore/          Logic with no UI, covered by Tests/
  Pomodoro.swift           The pomodoro cycle as a plain value; callers pass the time in
  Agenda.swift             Which event shows beside the notch, and when that next changes
  Usage.swift              Parsing of Claude Code's and Codex's own limit reports
  StatusLineHook.swift     Connecting and disconnecting Claude Code's status line
  IslandScreens.swift      The open island's screens and the two-finger swipe, as plain values
Sources/Brow/              The app
  BrowApp.swift            Entry point
  IslandController.swift   The window: where it sits, hover, click, right-click, swipe, opening and closing
  IslandView.swift         The island's shape, the closed, peeking and open layouts, the design's colors
  Cards.swift              The four cards, and the calendar's wide card for a screen of its own
  IslandMenu.swift         The right-click menu
  SettingsWindow.swift     The Settings window and its six panes
  AppModel.swift           The models in one place, and the island's sizes
  Preferences.swift        How the island opens, the master switch for beside the notch, the screens
  KeepAwake.swift, PomodoroModel.swift, UsageModel.swift, CalendarModel.swift
docs/STATUS.md             Features, progress, what isn't built, and what to improve
```

To add a feature: write an `@Observable` model, add it to `AppModel`, add a case to `Widget` in
`IslandScreens.swift`, a card in `Cards.swift`, and a pane in `SettingsWindow.swift`.

## AI usage: where the numbers come from

- **Codex** writes its limits into its session logs under `~/.codex/sessions`. The island reads the end of the
  newest log. Nothing to set up; numbers are as fresh as your last Codex reply.
- **Claude Code** pipes a JSON report, limits included, into its status-line command. Turning on
  **Claude Code** under Settings → AI Usage changes that command in `~/.claude/settings.json` to
  `tee <file> | ( your own command )`, so the island gets a copy and your status line looks as it did.
  The original file is kept beside it as `settings.json.brow-backup`, and turning the setting off puts
  your command back. Limits appear after the next reply in a Claude Code session, and only on a subscription plan.

## Not built

Usage warnings at a threshold, hiding over full-screen apps, and "time to leave" (it needs your location and a route lookup). On a screen without a notch the island still works, at the top
center, and takes clicks in a 180 pt wide strip of the menu bar there.
