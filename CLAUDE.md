# CLAUDE.md

## Project: Avodoro

Avodoro is a small macOS pomodoro timer shaped like a halved avocado. It floats above other windows, lets me type what I'm working on, and when a session ends it appends one line to a daily log file inside my Obsidian vault.

The log is the real product. Later, a separate AI analysis tool will read it to find patterns in my focus, energy and breaks. The log format must stay stable and machine-parseable.

This is a personal tool for one user on one Mac. It will not be distributed. "Avodoro" is a working name.

## Current status

- Milestone: 8 (robustness) done. All eight milestones are built. 95 tests pass.
- M8 works:
  - `SystemEvents` (`Support/`): `NSWorkspace.willSleepNotification` → pause; `com.apple.screenIsLocked` → pause if the setting is on; unlock is only logged. Never resumes.
  - Crash recovery: `SessionRecorder` saves `TimerEngine.snapshot(heartbeat:)` to `active-session.json` on every state change (`onStateChange`) and every 30 s while running; idle deletes the file. `RecoveryRecord` = session, finishing line, task text, heartbeat.
  - On launch a record puts the engine in the new `.recovering` phase: the avocado asks "Unfinished session from 14:05. Log it or discard?". Log it → `stopped`, ending at the heartbeat, actual = planned − remaining then, open pause counted. Starting a new session instead logs the old one first (same rule as the energy picker). A record that had already finished (energy question open) is written at launch without asking.
  - Quit during a running/paused session: alert "Stop and log this session?" with Stop and log / Discard / Cancel. Quit during the energy question writes the line without energy. Quit while recovering keeps the file, so it asks again next launch. Quitting always waits (`.terminateLater`) until pending writes finish. On log out / shut down (`willPowerOffNotification`) it stops and logs without an alert.
- To test by hand for M8:
  - Start a session and lock the screen (⌃⌘Q): unlocked, the avocado is paused and stays paused. Same after closing the lid / sleeping.
  - Start a session, wait over 30 s, then `pkill -9 -x Avodoro` and `make run`: the avocado asks about the unfinished session. Log it → a `stopped` line ending at the last heartbeat (up to 30 s before the kill). Repeat with Discard → no line.
  - Quit from the menu during a session: Stop and log writes a `stopped` line; Discard writes nothing; Cancel keeps the session running.
  - If the lock pause never happens, run `log show --info --predicate 'subsystem == "com.example.avodoro"' --last 10m` and look for "Screen locked"; if it's missing, the undocumented notification doesn't arrive on this macOS. Tell me rather than working around it.
- M7 (end of session):
  - `CompletionAlerts` (`App/`): on time up (never on Stop) plays the chosen system sound and, if enabled, posts a notification ("Focus session done" + the task, or "Break is over" / "Ready to focus?"). Permission is requested at the first session end, in a `Task`; any failure is logged (`category == "app"`) and ignored, so sound and animation still happen. The notification has no sound of its own.
  - `TimerEngine.onComplete` now passes `(type, taskText)` captured before the line is written; `completionCount` counts time-ups.
  - Pit completion motion: `keyframeAnimator` bounce 1 → 1.12 → 0.96 → 1 (0.4 s), or an opacity fade with Reduce Motion.
  - `UserNotifications` is imported with `@preconcurrency` (the framework isn't annotated for Swift 6 yet).
- To test by hand for M7:
  - Run a 5 min session to the end: you hear the sound chosen in Settings, the pit bounces once, and a notification appears. The first time macOS should ask for permission; if it doesn't, or nothing appears, run `log show --info --predicate 'subsystem == "com.example.avodoro"' --last 10m` and send me the output.
  - With Reduce Motion on (System Settings › Accessibility › Display), the pit fades instead of bouncing.
  - Sound off / notification off in Settings are respected. Stop never plays the sound.
- M6 (settings):
  - Settings window (`Views/SettingsView.swift`, `@AppStorage`): log folder with Choose… (`NSOpenPanel`, directories only) and "Inside vault: <name>" / "This folder is not inside an Obsidian vault." / "Folder not found."; presets (up to 6 rows, steppers 1–120, add/remove); default break; discard shorter than; ask energy; pause on screen lock; sound at end + system sound picker (previews on change); notification at end; size Small/Medium/Large (live); launch at login.
  - `SettingsStore` (`Support/`) registers defaults, reads typed values, reloads on `UserDefaults.didChangeNotification`, and pushes changes: folder → `LogService.setFolder` (flushes the pending queue), configuration → `TimerEngine.configuration`. Keys kept from before: `logFolderPath`, `avocadoSize`.
  - `VaultDetector` walks up from the folder looking for a `.obsidian` directory.
  - First run (no folder): the preset band shows "Choose a log folder", which opens Settings. Sessions still run; their lines wait in the queue.
  - Avocado: five or six presets go in two rows (one row didn't fit the flesh); a 3-digit countdown ("120:00") shrinks slightly to stay inside the pit.
  - Launch at login uses `SMAppService.mainApp`; its state is read from the system, not stored. Unverified with ad hoc signing, and it registers the app at its current path (`build/Build/Products/Debug/Avodoro.app`), so `make clean` breaks it until the next build.
  - Swift 6.1 compiler crash: `Binding(get:set: someMethod)` crashed IRGen; a closure literal avoids it (comment in `SettingsView.swift`).
- To test by hand for M6:
  - Settings… → choose a folder inside your vault (label shows the vault name) and one outside (orange warning). Queued sessions are written as soon as a folder is chosen; the red dot disappears.
  - `defaults delete com.example.avodoro logFolderPath`, restart: the avocado says "Choose a log folder"; clicking it opens Settings in front.
  - Edit presets (add up to 6, remove, change values): the chips on the avocado update right away.
  - Size picker resizes the avocado live.
  - Ask energy off: a focus session ends without the energy question.
  - Discard shorter than 0 min: stopping after a few seconds still logs a `stopped` line.
  - Launch at login on: Avodoro appears in System Settings › General › Login Items; after logging out and in, it starts.
- M5 works:
  - Position memory: `setFrameAutosaveName("AvocadoPanel")`; on launch and when displays change (`didChangeScreenParametersNotification`), a panel with less than 40 × 40 pt on any screen moves to the bottom right of the main screen (`Window/PanelPlacement.swift`, pure and tested).
  - Sizes: `AvocadoSize` (small 0.8, medium 1, large 1.25) from the `avocadoSize` key; the panel follows Settings changes live, resizing around its centre, clamped to its screen.
  - Context menu: built in AppKit in `AvocadoPanel.sendEvent` (right click or control-click anywhere, including the skin): Start / Pause or Resume, Stop / Settings… / Hide avocado.
  - `⌘.` stops a session when the panel is key (`AvocadoPanel.performKeyEquivalent`).
  - When a session starts, the task field loses focus. After a break, the restored task text is selected the next time you click the field. The view never takes focus by itself, so it can't steal typing from the app you're in.
  - Settings… in the context menu uses SwiftUI's `openSettings` captured from the panel's `NSHostingView` (verified working).
- M4 works:
  - `AvocadoShape` with tuned control points (the spec's starting path read as a pear): right shoulder to (0.85, 0.42) c1 (0.70, 0.00) c2 (0.77, 0.24); right belly to (0.50, 1.00) c1 (1.01, 0.78) c2 (0.95, 1.00); left side mirrored. Joins at y = 0.42 stay smooth (collinear controls). Skin is 6 % of the width (7 % looked heavy and squeezed the energy question).
  - `AvocadoView` in every state (idle, running, paused, finishing with `EnergyPicker`, warning dot with tooltip), `PitView` with ring and countdown. All text passes WCAG AA (`PaletteTests`). Snapshots: `make snapshot` → 21 PNGs.
  - Energy picker was pulled forward from M7 (otherwise each focus session would wait 120 s). It sits lower than the task band (centre y = 0.43) because the flesh is too narrow higher up; "Skip" shares the row with the 1–5 buttons to stay clear of the ring.
  - `LogService` connects the engine to `LogWriter` with a serial task chain and computes the warning text.
  - Menu bar: countdown label while running, Start / Pause or Resume / Stop, Open today's log (Obsidian URL, Finder fallback).
  - **API deviation:** a `TimelineView` inside the `MenuBarExtra` label puts SwiftUI into an endless update loop at launch (100 % CPU, app never finishes launching; seen on macOS 27). The menu bar label uses `MenuBarTicker` (a 1 s `Timer` that only redraws while running) instead. The avocado itself uses `TimelineView` as specified.
  - `FirstMouseHostingView` accepts the first click, so controls work while another app is frontmost.
  - Task placeholder is drawn by the view (the system placeholder is nearly white in dark mode), and the avocado forces `colorScheme = .light` so the caret and typed text stay dark.
  - **API deviation:** `.help()` tooltips never appear on the panel (system tooltips only show while the app is active, and the panel never activates it; seen 2026-10-16). The warning reason is drawn in the panel instead: a small card over the task band, shown while hovering the dot or after clicking it (click again or on the card to close).
- M3: `TimerEngine` + `Clock` (`Sources/Avodoro/Timer/`). Never ticks; schedules time-up and the 120 s energy timeout. Choices: completed end time = time-up moment; `actual` = planned − remaining; stopping while paused counts the open pause; default focus preset 15 min. `Session` is Codable for M8. `systemWillSleep()` / `screenDidLock()` exist, observers come in M8.
- M2: `LogFormat`, `PendingQueue` (stores structured `{day, entry}`; undecodable lines kept), `LogWriter` actor (flush before write, never creates the folder, outcome `.written` / `.queued` / `.lost`). Known limitation: if the queue file can't be rewritten after a flush, lines may be written twice (chosen over losing them).
- M1: XcodeGen project, Makefile, menu bar, floating `AvocadoPanel`. Drag via `DragHandleNSView` under the skin (`hitTest` only on the skin band, `performDrag`), chosen over `isMovableByWindowBackground` because SwiftUI in `NSHostingView` doesn't reliably report `mouseDownCanMoveWindow`.
- Known gaps (by plan): context menu, `⌘.`, selecting the task text after a break, position memory, sizes (M5); Settings window and first-run state (M6); sound, notification, bounce (M7); sleep/lock observers, recovery, quit confirmation (M8).
- Next: no milestones left. Remaining work is the hand-test lists below, then fixes from what they find.
- Hand-tested 2026-10-15 (M1; one desktop, three displays): floating, full-screen apps, drag by skin only, Show/Hide, Settings in front, Quit all pass. Clicks on the transparent corners do **not** pass through (accepted for now). Not yet tested: Spaces, moving between displays.
- Hand-tested M5 on 2026-10-16: position memory across relaunch (pass); right-click menu and its Settings… (pass, so `openSettings` works from the panel's `NSHostingView`). Bug found and fixed: after Return the task text stayed selected and the next keys replaced it; `@FocusState = false` didn't end editing in the panel, now `makeFirstResponder(nil)` does, after Return and when a session starts or resumes. Still to test: the Return fix, `⌘.` (Command + period key), size, selection after a break, display disconnect.
- To test by hand for M5:
  - Click the task field and type while another app stays frontmost (its window title stays active); press Return, then keys should no longer go into the field.
  - Drag the avocado, quit, relaunch: same place. Move it to another display, disconnect that display: it comes back to the main screen.
  - Right click on the flesh, the skin and the pit: the menu appears. Its Settings… opens the Settings window in front.
  - `⌘.` stops a running session after you've clicked into the avocado.
  - `defaults write com.example.avodoro avocadoSize large`, restart: bigger avocado, same place. `defaults delete com.example.avodoro avocadoSize` to go back.
  - After a break ends, click the task field: the old text is selected, typing replaces it.
- To test by hand for M4 (done 2026-10-16 except where noted):
  - Set the log folder (command above), restart, run a 5 min focus session to the end, rate energy; check the line in `YYYY-MM-DD.md`.
  - Pause and resume by clicking the pit; Stop from the menu after more than 1 min (logs `stopped`) and before 1 min (nothing logged).
  - Type in the task field while another app stays frontmost; press Return to start.
  - Menu bar shows the countdown and it updates every second.
  - Open today's log opens the file in Obsidian.
  - Without a folder: the red dot appears; hovering it (or clicking it) shows the reason card.
- Hand-tested M4 on 2026-10-16: Stop after more than 1 min logs `stopped` (pass). Fixed after testing: white placeholder, Skip too close to the pit, no tooltip on the red dot.
- Update this section at the end of every milestone: what works, what is known to be broken, what's next, and what I need to test by hand.

## Tech stack

- Swift 6 (language mode 6, strict concurrency). SwiftUI for views, AppKit where SwiftUI is not enough (the floating window).
- Minimum macOS 14.0 (needed for `@Observable` and `openSettings`).
- XcodeGen generates the Xcode project from `project.yml`. The `.xcodeproj` is generated and gitignored.
- Tests use Swift Testing (`import Testing`).
- Zero third-party dependencies. Ask before adding one.

Why native: the app needs a transparent, custom-shaped, always-on-top window that accepts keyboard input without stealing focus from other apps. This is straightforward in AppKit and painful in Python GUI toolkits or Electron.

### Prerequisites

- Full Xcode 16 or newer, not only the Command Line Tools. `xcode-select -p` must point inside Xcode.app.
- `brew install xcodegen`

## Commands

Create these Makefile targets in milestone 1 and keep them working:

```
make gen        # xcodegen generate
make build      # xcodebuild -scheme Avodoro -derivedDataPath build build
make test       # xcodebuild -scheme Avodoro -derivedDataPath build test
make snapshot   # renders AvocadoView in every state to snapshots/*.png
make run        # build, then open build/Build/Products/Debug/Avodoro.app
make clean
```

Always pass `-derivedDataPath build` so output paths are predictable. Run `make build test` before reporting any task as done.

## Project structure

```
project.yml
Makefile
Sources/Avodoro/
  App/       AvodoroApp.swift (@main, MenuBarExtra, Settings scene), AppDelegate.swift
  Window/    AvocadoPanel.swift (NSPanel subclass), PanelController.swift
  Timer/     TimerEngine.swift, Session.swift, Clock.swift
  Log/       LogFormat.swift (format + parse, pure functions), LogWriter.swift, PendingQueue.swift
  Views/     AvocadoView.swift, AvocadoShape.swift, PitView.swift, EnergyPicker.swift, SettingsView.swift
  Support/   SettingsStore.swift, Recovery.swift
Tests/AvodoroTests/
  LogFormatTests.swift, LogWriterTests.swift, TimerEngineTests.swift, SnapshotTests.swift
snapshots/   (gitignored) PNG output of make snapshot
```

Architecture rule: views are thin. All behavior lives in `TimerEngine`, `LogFormat` and `LogWriter`, and all of it can be tested without any UI. `TimerEngine` takes a `Clock` protocol, so tests never wait in real time.

### project.yml essentials

- One app target `Avodoro` and one unit test target `AvodoroTests` hosted by the app.
- `LSUIElement = YES`. No Dock icon; the app lives in the menu bar and in the floating avocado.
- No App Sandbox. The app writes to a folder I choose anywhere on disk, including iCloud Drive. No entitlements file.
- Ad hoc signing: `CODE_SIGN_IDENTITY = "-"`, no team.
- Bundle id `com.example.avodoro` (placeholder, I will change it).
- `MACOSX_DEPLOYMENT_TARGET = 14.0`, `SWIFT_VERSION = 6.0`.

## Product spec

### The floating window

- `AvocadoPanel` subclasses `NSPanel` with style mask `[.borderless, .nonactivatingPanel]`.
- Override `canBecomeKey` to return `true`. Borderless windows refuse key status by default, and the task field needs keyboard input. `canBecomeMain` returns `false`.
- `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`.
- Transparent: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`. Call `invalidateShadow()` whenever the content changes size, otherwise the shadow keeps the old outline.
- Content is the SwiftUI `AvocadoView` inside an `NSHostingView`.
- I drag the avocado by its skin (the dark outer band). Controls inside must still receive their clicks. Options: `isMovableByWindowBackground`, or an AppKit view under the skin that calls `window?.performDrag(with:)` on mouse down. Pick what works and write down why.
- Remember the position with `setFrameAutosaveName("AvocadoPanel")`. On launch, if the saved frame is not on any connected screen, move the panel to the bottom right of the main screen.
- Default size is 240 × 320 pt. Settings offer Small (0.8×), Medium (1×) and Large (1.25×).
- Verify these on a real Mac and report the result. Do not assume them:
  - Typing in the task field works while another app stays frontmost. If it doesn't, activate the app when the field is clicked and give focus back after the session starts.
  - Clicks on the transparent corners pass through to the window below, or not.

### Menu bar

`MenuBarExtra` with the SF Symbol `leaf.fill`. While a session runs, the label shows the remaining time (`12:34`). Items:

- Show avocado / Hide avocado
- Start, Pause or Resume, Stop (depending on state)
- Open today's log: open `obsidian://open?path=<percent-encoded absolute path>`. If that fails, reveal the file in Finder.
- Settings…: call `NSApp.activate()` first, then the `openSettings` environment action. Menu bar apps otherwise tend to open Settings behind other windows.
- Quit

### Session types and states

Two session types: `focus` and `break`.

```
idle ──start──▶ running ──pause──▶ paused ──resume──▶ running
                  │                  │
                  ├── time up ───────┤
                  └── stop ──────────┴──▶ finishing ──(rating | skip | timeout | new start)──▶ write line ──▶ idle
```

Rules:

- Never count ticks. When running, store `endDate`; remaining time is `endDate - now`. The UI refreshes once per second with `TimelineView(.periodic(from:by: 1))`.
- Pause stores the remaining time and opens a pause interval. Resume sets `endDate = now + remaining` and adds the interval to `pausedSeconds`.
- `actualSeconds` counts focused time only. Pauses are excluded.
- Stop: if `actualSeconds` is below the discard threshold (default 60 s), drop the session without logging. Otherwise its status is `stopped`.
- Time up: play the sound, post the notification if enabled. Status is `completed`.
- `finishing`: for focus sessions with "Ask energy" on, show the energy picker. It closes on a rating, on Skip, after 120 s, or when I start a new session. Then the line is written. Break sessions skip the picker and are written immediately.
- After a focus session, suggest a break with the default break length. After a break, suggest focus with the last focus preset, and keep the previous task text in the field, selected, so typing replaces it.
- I can edit the task text while the session runs. The logged description is the text at the moment the session finishes.
- If the Mac sleeps during a running session, pause it. If the screen locks during a running session, pause it (setting, on by default). Use `NSWorkspace.willSleepNotification` and the distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`. The lock notifications are undocumented; if they are unreliable, tell me instead of building a workaround. Never resume automatically.

### Crash and quit recovery

- On every state change, save the active session to `~/Library/Application Support/Avodoro/active-session.json`, including a heartbeat timestamp that updates every 30 s while running.
- On launch, if that file exists, the avocado asks: "Unfinished session from 14:05. Log it or discard?" Logging uses the last heartbeat as end time and status `stopped`.
- On Quit during a running session, ask: "Stop and log this session?" with Stop and log, Discard, Cancel.

### Settings

Stored in `UserDefaults` via `@AppStorage`.

- Log folder: none by default, must be chosen on first run
- Presets in minutes: 5, 10, 15, 20 (editable, each 1 to 120, at most 6 presets)
- Default break: 5 min
- Ask energy after focus: on
- Sound at end: on, system sound "Glass"
- Notification at end: on
- Pause on screen lock: on
- Discard sessions shorter than: 1 min
- Avocado size: Medium
- Launch at login: off (`SMAppService.mainApp`)

Log folder details:

- Chosen with `NSOpenPanel`, directories only.
- Show the full path. Walk up the parent folders looking for a `.obsidian` folder. If found, show "Inside vault: <vault name>". If not, show a non-blocking warning: "This folder is not inside an Obsidian vault."
- First run without a folder: instead of the presets, the avocado shows "Choose a log folder" and opens Settings when clicked.

Notifications: use `UNUserNotificationCenter` and ask for permission at the first session end, not at launch. If authorization fails (possible with ad hoc signing), fall back to sound and the completion animation and log the error with `os.Logger`. Never block on it.

## The log format (schema 1)

This is a contract with a future analysis tool. Treat it as a public API.

### File

- Path: `<logFolder>/YYYY-MM-DD.md`. The date is the local date when the session started. A session that crosses midnight goes into the file of its start date.
- If the file does not exist, create it with this frontmatter followed by one empty line:

```
---
type: pomodoro-log
date: 2026-10-15
tz: Europe/Rome
schema: 1
---

```

`tz` is `TimeZone.current.identifier` when the file is created.

### Line

One line per session, appended at the end of the file:

```
- 09:02-09:27 Write blog post draft #writing [type:: focus] [planned:: 25] [actual:: 25] [status:: completed] [energy:: 4]
- 09:27-09:32 Break [type:: break] [planned:: 5] [actual:: 5] [status:: completed]
- 10:40-10:52 Refactor parser #code [type:: focus] [planned:: 20] [actual:: 9] [status:: stopped] [paused:: 3] [energy:: 2]
```

Fields always appear in this order. The first four bracketed fields are required, the rest are optional.

- `HH:MM-HH:MM`: local start and end time, 24 hour clock, ASCII hyphen. An end earlier than the start means the session crossed midnight.
- Description: the sanitized task text. Tags such as `#writing` stay inside the text, so Obsidian indexes them as normal tags.
- `type`: `focus` or `break`
- `planned`: planned minutes, integer
- `actual`: focused minutes without pauses, rounded to the nearest minute
- `status`: `completed` or `stopped`
- `paused`: paused minutes, only when greater than 0
- `energy`: 1 to 5, only for focus sessions that I rated
- `tz`: IANA time zone, only when it differs from the file's frontmatter `tz`

The fields use Dataview inline field syntax so they are queryable in Obsidian. The app must not depend on Dataview being installed.

Start and end are truncated to the minute and `actual` is rounded, so `end - start` will not always equal `actual + paused` exactly. Parsers must allow a difference of 1 minute.

### Sanitizing the description

- Trim, and collapse all whitespace including newlines into single spaces.
- Replace `[` with `(` and `]` with `)`, so the text can never look like a field.
- Maximum 200 characters. Cut at a word boundary and add `…`.
- Empty focus description becomes `(untitled)`. Empty break description becomes `Break`.

### Reference regex

The parser in `LogFormat.swift`, and any future parser, must accept exactly this:

```
^- (\d{2}:\d{2})-(\d{2}:\d{2}) (.*?) \[type:: (focus|break)\] \[planned:: (\d+)\] \[actual:: (\d+)\] \[status:: (completed|stopped)\](?: \[paused:: (\d+)\])?(?: \[energy:: ([1-5])\])?(?: \[tz:: ([^\]]+)\])?$
```

Lines that don't match are not sessions. I may write my own notes in these files. Ignore them.

### Writing rules

- Append only. Never rewrite, reorder or delete existing content, including lines I wrote by hand.
- If the file doesn't end with a newline, write one before the new line.
- Wrap the append in `NSFileCoordinator`. The vault may live in iCloud Drive, and Obsidian may have the file open.
- If the folder is missing or the write fails, save the line with its target date in `~/Library/Application Support/Avodoro/pending.jsonl`, show the warning dot on the avocado, and retry before each next write and whenever the folder setting changes. A line is never lost silently.
- Never write anywhere except the log folder and the Application Support folder.

Changing the format: ask me first. Then bump `schema`, update this section, and keep the parser able to read older schemas.

## Visual design

The avocado is the one memorable element. Everything else stays quiet: no extra chrome, no cards, no decoration outside the fruit.

### Shape

A halved avocado seen from the front:

- Skin: the outer outline, filled dark green. It doubles as the drag handle.
- Flesh: the same outline inset by about 7% of the width, filled with a radial gradient from pale yellow-green in the center to brighter green near the skin.
- Pit: a circle centered at (0.50, 0.70) of the frame, diameter 0.40 × width. It shows the countdown.
- Progress ring: a 6 pt stroke around the pit, in the flesh, darker green, rounded caps. It starts at 12 o'clock and grows clockwise as time passes.

Starting path for `AvocadoShape`, in normalized coordinates (0 to 1 on both axes, y pointing down), as one closed path:

```
move to  (0.50, 0.00)
curve to (0.82, 0.42)  control1 (0.66, 0.00)  control2 (0.70, 0.22)   right shoulder
curve to (0.50, 1.00)  control1 (1.00, 0.72)  control2 (0.95, 1.00)   right belly to bottom
curve to (0.18, 0.42)  control1 (0.05, 1.00)  control2 (0.00, 0.72)   left belly
curve to (0.50, 0.00)  control1 (0.30, 0.22)  control2 (0.34, 0.00)   left shoulder
close
```

The control points make the curves join smoothly at y = 0.42 and put the widest point near y = 0.72. This is a starting point, not a final shape. Tune it by looking at the snapshots until it reads as an avocado and not as a pear or an egg.

### Palette

- Skin `#34461C`
- Flesh edge `#9BBE45`
- Flesh center `#E4ECA0`
- Progress ring `#5E7F2A`
- Pit `#6B4226`, with a soft highlight `#8C5B35` at its top left so it looks round
- Text on flesh `#2C3A12`
- Text on pit `#F2E6CF`
- Warning dot `#B5432A`

The avocado keeps the same colors in light and dark mode. It is an object, not a UI surface. Check that text on flesh and on pit meets WCAG AA contrast for small text.

### Type

- SF Pro Rounded everywhere (`.system(size:weight:design: .rounded)`). It matches the soft shape.
- Countdown: 26 pt semibold with `.monospacedDigit()` so the digits don't jump.
- Task text, presets and labels: 12 pt regular or medium.
- Sentence case for all copy. No all caps.

### Layout

Bands in normalized y, everything center aligned:

```
0.12 to 0.22   mode label "Focus" or "Break" (click toggles, idle only)
0.24 to 0.33   preset chips 5 10 15 20 (idle only, selected chip filled)
0.36 to 0.50   task field, 2 lines max, placeholder "What are you doing?"
0.50 to 0.90   pit with countdown and progress ring
```

```
            .---.
          /       \
         /  Focus  \
        | 5 10 15 20 |
       |  What are    |
      |   you doing?   |
     |      .---.       |
     |    /       \     |
     |   |  15:00  |    |
      \   \       /    /
       \    '---'     /
         '._______.'
```

### Interaction

- Idle: click a preset to select it. Click the pit or press Return in the task field to start.
- Running: click the pit to pause or resume. Right click anywhere opens a context menu: Pause or Resume, Stop, Settings…, Hide avocado. `⌘.` stops the session when the panel is key.
- Paused: the countdown is dimmed and a small pause glyph appears under it. No blinking.
- Finishing (focus only): the task band shows "How was your energy?" with five small round buttons 1 to 5 and a Skip link. The pit shows a check mark.
- Warning (no folder, or lines waiting in the pending queue): a small dot on the skin at the top right. Hovering shows the reason in plain words, for example "Log folder not found. 2 sessions are waiting to be written."
- Accessibility: every control has a label, for example "Start 15 minute focus session", "Pause", "Energy 3 of 5". Respect Reduce Motion.

### Motion

One moment only: when a session completes, the pit does a short scale bounce (about 0.4 s). With Reduce Motion on, use a simple fade. The progress ring moves linearly. Nothing else animates.

## Testing and verification

- `LogFormatTests`: format every combination of type, status and optional fields; sanitizing (newlines, brackets, 200 character cut, empty text); midnight crossing; `tz` field only when it differs; round trip `parse(format(s)) == s`; the reference regex matches every formatted line.
- `LogWriterTests` in a temporary directory: creates the file with frontmatter; appends after existing content without changing it, including hand-written lines; handles a missing trailing newline; a missing folder sends the line to the pending queue; pending lines are flushed later in the original order.
- `TimerEngineTests` with a fake clock: start to completion; pause and resume accounting; stop below the threshold discards; stop above the threshold logs `stopped`; sleep pauses; the energy timeout writes the line without `energy`; starting a new session during `finishing` writes the pending line first.
- `SnapshotTests`: render `AvocadoView` with `ImageRenderer` on the main actor for idle, running at 0%, 50% and 90%, paused, finishing and warning, at all three sizes. Write PNGs to `snapshots/`, finding the repo root from `#filePath`. `ImageRenderer` may not draw AppKit-backed controls like `TextField`; in snapshot mode, draw a static `Text` in the same frame instead.
- After any visual change, run `make snapshot` and look at the PNGs yourself before you report the change as done.
- Some things only a real run can show: panel focus, dragging, Spaces, full-screen apps, notifications. List them in "Current status" at the end of the milestone so I can test them by hand.

## Milestones

Work on one milestone at a time. At the end of each one: `make build test` passes, "Current status" is updated, and the work is committed.

1. Scaffold: `project.yml`, Makefile, `.gitignore`, menu bar item, and an empty transparent panel that floats and can be dragged.
2. `LogFormat`, `LogWriter` and the pending queue, with tests. This comes before the UI on purpose: the log is the product.
3. `TimerEngine` and `Clock`, with tests.
4. `AvocadoShape` and `AvocadoView` in all states, snapshot tests, wired to the engine.
5. Panel details: key focus for typing, position memory, sizes, context menu, keyboard shortcuts.
6. Settings window, folder picker with vault detection, first-run state, launch at login.
7. End of session: energy picker, sound, notification, completion animation.
8. Robustness: sleep and lock pause, crash recovery, quit confirmation.

## Rules

- Ask before adding a dependency, changing the log format, or changing any decision in this file.
- If a macOS API behaves differently from what this file assumes, stop and tell me. Don't build a silent workaround.
- No network access in the app. No analytics, no telemetry.
- Prefer small, readable types over clever abstractions. This should stay a small app.
- Use `os.Logger` with the bundle id as subsystem for diagnostics, never `print`.
- Commit messages are short and imperative. One milestone or one fix per commit.

## Out of scope for v1

- The analysis tool. It will be a separate Python project that only reads the log.
- A global keyboard shortcut to show or hide the avocado.
- A compact mode that shows only the pit.
- Stats or charts inside the app.
- Writing into Obsidian's Daily Notes instead of a separate folder.
- iOS or any sync beyond what the vault folder already does.
