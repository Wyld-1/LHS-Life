# LHS Life — Requirements

What the app must do and the rules every change is held to. For how it's
built, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Product

LHS Life is the student-built companion app for La Salle High School, Yakima.
It turns the school's public calendar into a live bell schedule, puts lunch
ordering, grades and Schoology a tap away, and reminds students about the
things that are easy to forget.

- **Who:** students first (personal iPhones, school iPads), then teachers and
  staff. Parents can use it as "Not a student".
- **How it's used:** opened many times a day, for a few seconds at a time —
  before class, in the hallway, at lunch. Every interaction has to be instant
  and need no thought.
- **Where:** iPhone and iPad on iOS 17+, and Apple silicon Macs from the App
  Store. Live Activities need iOS 18.
- **Distribution:** free on the App Store. Sign-in is a school email address
  check on the device; there are no accounts.

---

## 2. Principles

A change that breaks one of these is revised before it ships.

### Instant
- Every tap responds within a frame.
- Networking, parsing, OCR and notification scheduling never block the main
  thread or the first frame.
- Launch waits only for the calendar (from cache if necessary), never for the
  web tabs, and the launch screen appears only if loading is actually slow.
- Nothing redraws more often than what it shows can change: the header updates
  once a minute, on the minute.

### Glanceable
- "What period is it, and how long is left?" is answered without opening the
  app (Live Activity) and without tapping inside it (header pill).
- The secondary line always says what's next: the next class, or the next
  event worth knowing about.

### Right, or quiet
- A wrong schedule is worse than none. Posted times beat inferred ones; a
  schedule posted as a picture is read rather than guessed; a day with no
  posted times uses the standard schedule for that kind of day.
- Holidays come only from Schedules-category events, so an event title that
  merely mentions a holiday can't cancel school.
- The Live Activity never shows a confident lie. After a student's last
  class it says "Done for today"; if it can't start, the student is told why.
- A guard that can end something must never be able to loop with the thing
  that starts it.

### Effortless
- Anything reachable is at most one tap away.
- Homework entry needs no navigation: a popup over the current screen, focused
  text field, current class preselected.
- Defaults are the ones most students want: Live Activities Every Day, and
  Professional Dress, Late Start and Home Game reminders on.

### Respectful
- No accounts, analytics, tracking or ads.
- The only data that leaves the device is what Live Activities need (the
  day's bell times, with no device ID or token) and once-a-day problem
  reports (a random install ID, app and iOS version, and what failed) — never
  names, emails, classes or anything typed.
- Alert settings stay on each device; identity and classes sync through the
  student's own iCloud.
- Calendar and Reminders access is requested only when the student asks to
  save something, and Calendar access is write-only.
- Switching the app icon always asks; nothing changes the Home Screen
  silently.

### Plain words
- Labels are short and say what happens: "Preview Live Activities", "Use
  Christmas Icon", "Change anytime in Settings". No explanations where a
  label will do; at most two short paragraphs anywhere.
- No jokes in settings or alerts.

### Native
- iOS 26+: liquid glass, native TabView with minimize-on-scroll, glass effects.
  iOS 17–25: equivalent materials. Version checks live in the component that
  needs them, not in containers.
- Settings is a stock grouped list.
- iPad gets a sidebar layout, not a stretched phone. The Mac runs the iPad app
  and hides what a Mac can't do (Lock Screen previews, icon switching).

### Maintainable
- Colors, fonts, spacing and animations come from `DesignSystem.swift`
  (`LS.*` spacing; no bare numbers in `.padding`/`.spacing`).
- `@Observable` only — no `ObservableObject` or `@Published` anywhere
  (enforced by `StaticAnalysisTests`).
- Comments explain *why*, especially when the obvious approach was tried and
  failed.
- Generated assets regenerate themselves (icon previews are rendered at build
  time).
- Nothing ships with placeholder art.

---

## 3. Features

### 3.1 Header pill
- Primary line: "22 min left in Chemistry", "Physics in 3 min", "School at
  8:00 AM", "Happy Friday!", "No school today", "Internship Day", and the AP
  exam name on a student's exam day.
- Secondary line: next class and time during school; otherwise the next
  relevant event (home games, Mass, assemblies; away games excluded).
- Progress fill in the current period's color.
- Updates on each minute and on returning to the app.
- Holding it for five seconds on a no-school day shows an easter egg.

### 3.2 Events tab
- Week strip over a day timeline: classes and events side by side, up to four
  overlapping columns.
- Zoom out to month and year; zoom icons follow the system's SF Symbols
  (`square.grid.month` on iOS 27).
- Schedule type shown for non-regular days.
- Event details: time (parsed from the title when an "all day" game names
  one), location, description, student-section theme, Save to Calendar.
- Pull to refresh on the day view; the calendar also refreshes on every
  return to the app.

### 3.3 Web tabs — Order, Grades, Schoology
- Lunch ordering, PowerSchool and Schoology, embedded and kept signed in.
- All three begin loading at launch; tapping a tab shows a page already loaded
  or its own progress, never a full-screen blocker.
- Tapping the active tab again returns it to its home page.
- Lunch gets a dark theme injected to match the app.

### 3.4 Homework
- Floating button (iOS 17–25) or tab-bar button (iOS 26+) opens a popup over
  the current screen.
- Class defaults to the current or next class; due date menu offers Tomorrow,
  Next Monday, or a picked date.
- Saves to Apple Reminders, in a list per class.

### 3.5 Live Activities
- Lock Screen card and Dynamic Island: class name and color, minutes to the
  next bell, the bell time, next class, and a progress bar. Before school: the
  first bell and the day's schedule as colored bands.
- Compact island: progress arc, and a gray bell with the next bell time
  ("8:55").
- Modes: Every Day (default), Abnormal Days, Off. Abnormal Days is any day
  that isn't one of the weekly patterns (Regular, Odd Block, Even Block,
  Thursday's "Late Start/…/Even Block" included): liturgies, early releases,
  assemblies, extended lunch, finals, special schedules.
- Starts when the student opens the app on a school day; a morning reminder
  offers to start it on days they haven't.
- Days with no school left for this student (after school, holidays, their
  Pathways day) never start a card.
- **Preview:** "Preview Live Activities" in Settings shows a frozen sample
  card marked PREVIEW. It works any
  time, never contacts the server, and ends from End Preview (red) or a
  swipe.
- **After the last bell** the card shows "Done for today" until the app
  ends it or the server's end broadcast at the day's last bell clears it.
- **iOS 18** is required for the card (broadcast channels); on iOS 17 none
  starts, and trying says "Needs iOS 18".
- **No phone limit.** One broadcast per bell serves the whole school, so no
  student is ever turned away.

### 3.6 Reminders

| Reminder | Default | Timing |
|---|---|---|
| Professional Dress | On, 9:00 PM | Night before if the time is noon or later, otherwise morning of |
| Late Start | On, 9:00 PM | Same rule; says when the first class starts |
| Home Games | On, 7:30 AM | Same rule; includes the student-section theme when posted |
| ASB | Off; ASB members choose days | Announcements before first period; Student Store before Break and Lunch |
| Start Live Activity | With Live Activities on | Morning of school days |
| Abnormal schedule | Only with Live Activities off | Morning of a day that isn't Regular, Odd Block or Even Block (the same rule as Abnormal Days) |

Settings shows each reminder as a row with its time ("9:00 PM") that opens a
screen with Remind Me, Time, and Arrives ("Night before" / "Morning of").

### 3.7 Settings
In order: My Info (Class Of / Not a Student), My Classes (name, color, on/off
for periods 0–8), App Icon (holiday windows only), Lock Screen (Live
Activities mode, Preview Live Activities; footer "Pin your live bell schedule
to your Lock Screen and Dynamic Island", Lock Screen only on iPad), Reminders,
ASB (members choose work days as glass capsules that flow together), Map,
Sign Out, Privacy Policy, Rate LHS Life. Footer: "LHS Life 1.2.1 · La Salle
High School · Yakima".

### 3.8 Holiday app icons
- Classic is the main icon. Halloween (October), Thanksgiving (Nov 1 through
  the Sunday after Thanksgiving) and Christmas (Dec 1 – Jan 6) are offered in
  their windows.
- First open in a window: a card with Classic and the holiday icon, holiday
  selected, button "Use Halloween Icon", subtitle "Change anytime in
  Settings." Once per holiday per year.
- Outside every window the App Icon section hides, unless a holiday icon is
  still on — then it stays so Classic is one tap away. Keeping a holiday icon
  all year is allowed.

### 3.9 Special days
- **Pathways:** juniors and seniors are off campus; the header says
  "Internship Day" and no schedule shows.
- **Serve-a-thon:** each grade serves 8:00–3:00 on its day, inferred from any
  one posted grade's event.
- **Class Orientation:** a grade-specific window replaces the generic all-day
  event.
- **Finals:** one finals event fills in every day of the finals table.
- **AP exams:** on an exam day a Settings banner offers AP Mode, which puts the exam in the header in place of the class schedule.

### 3.10 Siri and Shortcuts
- Spoken: next class, next bell, today's schedule, tonight's events, next
  Professional Dress day; open Lunch, Grades, Schoology; add homework.
- Values for automations: school start time, end time, schedule type, is there
  school — for today or any date; nothing on days without school.

### 3.11 Other
- iPhone call sheet: main office and support lines (Upper Room, Teen Link, 988).
- Campus map with pinch zoom.
- Rating prompt only after real use (5 different days over 10+ days), never on
  a day something broke; plus a permanent Rate LHS Life row.
- Delete All Data clears settings, iCloud data, web logins and the calendar
  cache, ends the Live Activity, and gives the device a new random ID for
  problem reports. The server holds nothing about the device to delete.

---

## 4. Server requirements

- Store only bell times from phones: each distinct schedule once, no device
  ID or push token, expiring after 3 days.
- Broadcast once per bell in the union of today's schedules, to both the
  production and sandbox channels, within two minutes of the bell; one end at
  the day's last bell.
- No phone limit, inside Cloudflare's free plan.
- `/health` says whether the latest bell went out ("ok" or "FAILED") so an
  uptime monitor can alert.
- A status dashboard an administrator can read without help: charts of
  today's bells (sent, missed, reported too late), how long Apple took, and
  the week's problems with device counts; dropdowns for the day, schedule and
  problem kind. The same data as JSON at `/status.json`.
- A one-click test (`/test-broadcast`) that explains Apple's answer; ending
  every production card needs an explicit confirm.
- Problem reports expire after 7 days.
- Every page but `/health` behind the shared secret.
- The Broadcast Capability stays on for the App ID; turning it off deletes
  every channel permanently.
- Until students update from 1.2, the legacy one-push-per-phone path keeps
  working (about 35 phones on the free plan).
- Before release, the app's Worker URL must point somewhere the school can
  keep running.

---

## 5. Reference

### Color palette

| # | Name | Hex |
|---|---|---|
| 0 | Slate | #94A3B8 |
| 1 | Coral | #FF6B6B |
| 2 | Peach | #FB923C |
| 3 | Gold | #F5B800 |
| 4 | Mint | #34C78A |
| 5 | Sky | #38BDF8 |
| 6 | LaSalle Blue | #3A6FD8 |
| 7 | Lavender | #A78BFA |
| 8 | Rose | #F472B6 |
| 9 | Teal | #2DD4BF |

Default class colors run in rainbow order from period 1; periods 0 and 8 start
off.

### Haptics (`HapticEngine.shared`)

| Method | Use |
|---|---|
| `tap()` light impact | Toggles, buttons |
| `bump()` medium impact | Header pill, larger actions |
| `tick()` selection | Picking colors, classes, icons, menu values |
| `success()` | Homework saved, confirmations |
