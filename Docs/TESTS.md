# LHS Life — Tests

Two layers: **unit tests** for the logic that decides what a student sees, and
**manual checks** for what only a device can show (Live Activities,
notifications, icons). See [ARCHITECTURE.md](ARCHITECTURE.md) for the code
they cover.

---

## 1. Running the unit tests

The `LHS Life` scheme's Test action uses the **Debug** configuration — Release
builds can't be loaded by `@testable import`. In Xcode, ⌘U. From a terminal:

```bash
xcodebuild test -project "LHS Life.xcodeproj" -scheme "LHS Life" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing "LHS LifeTests"
```

No network, no UI, no clock: every test builds its own dates with
`makeDate(...)` (Pacific time) and its own events and schedules from
`TestHelpers.swift`.

**Status (Oct 2026, version 1.3.0): 118 tests, all pass** (Debug
configuration).

---

## 2. Unit test suite

| Class | Tests | What it guards |
|---|---|---|
| `ScheduleEngineTests` | 18 | "What period is it?" — every `DayState`, period edges, disabled periods, Break/Lunch, progress bounds, display names |
| `ScheduleEngineHeaderTextTests` | 8 | Header wording for each state; minutes round up |
| `ICalParserTests` | 12 | RFC 5545: all-day vs timed, UTC vs floating, line unfolding, escapes, required fields, multiple events |
| `BellScheduleParserTests` | 14 | Stacked-table format: names, times, durations, PM inference, schedule type, nil cases |
| `BellScheduleDetectorTests` | 16 | Categorizing events: schedules, athletics, Mass, staff, holidays, Professional Dress; priority and case rules |
| `PathwaysServiceTests` | 13 | School year boundary, junior/senior eligibility, Pathways events and days |
| `PeriodConfigTests` | 9 | Display names, defaults for periods 0–8 |
| `ColorPaletteTests` | 6 | Ten colors, valid hex, index clamping |
| `DateHelperTests` | 7 | Homework due dates: tomorrow, next Monday from every weekday |
| `SchoolEventTests` | 4 | Day keys, bell-schedule detection |
| `BellReporterTests` | 4 | The bell minutes sent to the Worker: starts and ends, deduplicated and sorted; the last end included; an empty day; minutes in Pacific time, not the phone's zone |
| `StaticAnalysisTests` | 7 | Architecture rules, enforced by scanning source (below) |

### 2.1 Notes on specific classes

- **ScheduleEngineTests** use a standard day on Tue 2026-05-05 (Period 1
  8:00–8:50 through Period 7 14:10–15:00, with Break and Lunch). These matter
  most: the header, the Live Activity start/end decision and Siri all go
  through `ScheduleEngine.state`.
- **BellScheduleParserTests** call `parse(from:)`, which returns
  `[BellSchedule]` (one finals event can fill several days); single-day cases
  take `.first`. Block days are `.oddBlock` / `.evenBlock` — there is no
  `.block`.
- **BellScheduleDetectorTests** include the holiday keywords. `SchoolEvent.isHoliday`
  additionally requires the Schedules category; that rule isn't covered yet
  (§3).

### 2.2 StaticAnalysisTests

| Rule | Status |
|---|---|
| No `@Published` | Passes |
| No `@EnvironmentObject` | Passes |
| No `ObservableObject` | Passes — `RemindersService` is now `@Observable` |
| No `didSet` disk writes in `UserSettings` | Passes |
| No bare numbers in `.padding()` / `.spacing()` in `UI/` — use `LS.*` | Passes |
| `[shared]` files import neither UIKit nor SwiftUI | Passes |
| No `// TELEMETRY` debug prints | Passes |

### 2.3 The Worker

The Worker's logic (bell storage, the broadcast cycle, `/health`, report
expiry) is tested with a Node harness that runs the Worker against a mock KV:
24 tests, all passing. The harness is kept outside the repo for now. It
should be checked in, under `Scripts/` or a `worker-tests/` folder, so the
Worker is tested alongside the app.

---

## 3. Gaps — tests worth adding

Ordered by how much a regression would hurt. Each was a real bug or a rule
that exists only in code today.

| Area | Test | Why |
|---|---|---|
| `SchoolEvent.isHoliday` | "Christmas Wreaths – 1st Collection" (Student Activities) is not a holiday; "Thanksgiving Break" (Schedules) is | Oct 15: a non-schedule event made a school day a holiday and looped the Live Activity |
| Live Activity timeline | `transitionDates` includes the last end; at 1:48 PM with only Period 6 (13:30–15:00) left, `resolveSlot` is not pre-school | Oct 15: "school starts 1:30 PM" mid-class. Needs the helpers moved out of the widget file into a testable shared file |
| `BellScheduleParser` formats | One-row-per-line ("8:00 — 8:40 ..... First Period"), finals tables filling several days | Oct 2 rally day parsed wrong before the line format existed |
| Floor rules | A Professional Dress day with no posted times gets the regular schedule; a picture-posted day is marked as floor-sourced | Picture days must be overridable by OCR |
| `CalendarStore.schoolDay(on:)` | Start/end for a normal day, a late start, a holiday (nil), a Pathways day for a junior (nil) | Shortcuts automations depend on it |
| `SchoolEvent` titles | `timeFromTitle` ("Football vs. X 7 PM"), `isHomeGame`, `sport` | Home game reminders and "all day" game times |
| `AppIconService` | `activeHoliday` on Oct 31 (Halloween), Nov 1 (Thanksgiving), Nov 29 2026 (last Thanksgiving day), Nov 30 (none), Jan 6 2027 (Christmas, from the previous year's window), Jan 7 (none) | Date windows are easy to get off by one |
| `IssueReporter.isConnectionProblem` | Timeout, connection lost, cannot find host, DNS failure → true; bad server response → false | Decides "network" vs "server" on /status |
| `ServeAThonService` | Any one grade's event lays out all four days | The feed omits a grade some years |
| `NotificationService` timing | Noon or later → night before; earlier → morning of | The rule behind every reminder |
| Worker harness in the repo | Check the mock-KV Node harness (§2.3) into the repo and document how to run it | Today it lives outside the repo, so a Worker change can ship untested |

---

## 4. Manual checks

Run on real devices before each App Store submission. The simulator can't show
a Live Activity on the iPad Lock Screen and can't open the App Store.

### 4.1 Live Activities (iPhone, a school day)
- [ ] Open the app before school: card shows "Today", the schedule type, the
      first bell, and colored bands.
- [ ] During a class: name, minutes left, "until" time, next class, bar moving.
- [ ] Passing time and Break show correctly.
- [ ] With the app closed, the card moves at each bell (server broadcast).
- [ ] A student on a different schedule, or with a period turned off, moves
      only at their own bells; other students' bells leave the card unchanged.
- [ ] Open the app during the **last** class: card shows that class, not
      "school starts".
- [ ] After the student's last class the card shows "Done for today".
- [ ] At the day's last bell, the one end broadcast clears every card
      (check two phones on different schedules).
- [ ] iOS 17 device: no card starts, and trying says "Needs iOS 18".
- [ ] Expanded Dynamic Island: progress bar fully visible, nothing clipped.
- [ ] A day with a non-schedule event mentioning a holiday: card stays up.

### 4.2 Preview
- [ ] Settings → Preview Live Activities: card appears on the Lock Screen and
      in the island with PREVIEW; row turns red "End Preview".
- [ ] Swipe the card away → row returns to "Preview Live Activities".
- [ ] Double-tap quickly → still only one card.
- [ ] iPad (real device): preview appears on the Lock Screen.
- [ ] Mac: the preview row is hidden.

### 4.3 Server
- [ ] During school, `/health` shows `broadcast: ok, last …`, never FAILED.
- [ ] `/status` shows today's bells marked Sent in green, at least one
      schedule, and each delivery bar green (Apple 200 on production).
- [ ] `/status` day dropdown switches to yesterday and back; Refresh works.
- [ ] `/status` reads well on a phone (no sideways scrolling) and in dark mode.
- [ ] `/test-broadcast` (sandbox) on an Xcode build: the card changes within
      seconds and the page explains Apple's answer.
- [ ] The uptime monitor on `/health` is running and alerts on FAILED.

### 4.4 Reminders
- [ ] Each reminder fires at its set time, night before vs morning of
      following the noon rule.
- [ ] Block days and late-start days get their reminders.
- [ ] Turning a reminder off removes already-queued ones.
- [ ] Reminder settings changed on iPhone don't change on iPad.

### 4.5 Icons
- [ ] Run `-demoClock` dates in each window (Oct 15, Nov 10, Dec 5) and one
      outside (Feb 10): the card appears once per window; Settings shows or
      hides App Icon correctly.
- [ ] "Use … Icon" switches the Home Screen icon after iOS's alert; Classic
      switches back.
- [ ] Edit an `.icon` in Icon Composer and build: the picker shows the new art.
- [ ] No holiday ships with placeholder art.

### 4.6 Calendar
- [ ] Leave the app in the background overnight; reopen: today's data.
- [ ] Pull down on the day view refreshes.
- [ ] A schedule posted as a picture shows the real times after a few seconds.
- [ ] iPad: the Events week doesn't jump when returning to the app (also in
      Stage Manager / a resized window).

### 4.7 Release
- [ ] Unit tests pass.
- [ ] Marketing version bumped for the app and the widget extension (they
      must match).
- [ ] `AppConstants.workerURL` points to the server that will keep running.
- [ ] Worker redeployed if `APNS Worker.json` changed (paste into the
      Cloudflare dashboard editor, Deploy), and the Worker harness passes.
- [ ] A Release build tested on a real iPhone, during school hours.
