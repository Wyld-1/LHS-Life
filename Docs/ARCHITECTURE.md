# LHS Life — Architecture

How the app is put together, from the outside in. For what it must do, see
[REQUIREMENTS.md](REQUIREMENTS.md); for how it's checked, see [TESTS.md](TESTS.md).

---

## 1. The big picture

```
                CalendarWiz iCal feed (the school's public calendar)
                                 │  HTTPS, on launch / foreground / pull
                                 ▼
┌──────────────────────────── LHS Life (iPhone · iPad · Mac) ─────────────────────────────┐
│  CalendarStore ── events + bell schedules ──► ScheduleEngine ("what period is it?")     │
│       │                                            │                                     │
│       ├─► Events tab, header pill, Siri/Shortcuts  ├─► Live Activity (start / end)       │
│       ├─► NotificationService (all reminders, local)                                    │
│       └─► SharedStore (App Group) ──► widget extension                                  │
│                                                                                          │
│  Lunch · PowerSchool · Schoology ── embedded WKWebViews                                  │
└──────────────────────────────────────┬──────────────────────────────────────────────────┘
                                       │ bell times + push token   │ problem reports
                                       ▼                           ▼
                         Cloudflare Worker ("APNS Worker.json")  ── /status page
                                       │ at every bell
                                       ▼
                         Apple Push Notification service ──► Lock Screen & Dynamic Island
```

**The app is self-contained.** Everything a student sees is worked out on the
device from the public calendar. There are no accounts and no analytics. The
only server is the optional Cloudflare Worker, which exists because a Live
Activity can't wake itself at 8:55 to say "next period" — something has to
push to it.

Targets:

| Target | What it is |
|---|---|
| `LHS Life` | The app. iOS 17+; Live Activities need iOS 18. Runs on Apple silicon Macs as an iPad app. |
| `LHS WidgetsExtension` | The Live Activity UI (Lock Screen + Dynamic Island). Home Screen widgets and the control widget exist but are **switched off** in `LHS_WidgetsBundle.swift` — mixing them with the Live Activity once stopped it from appearing on device. |
| `LHS LifeTests` | Unit tests. See TESTS.md. |
| `APNS Worker.json` | The Cloudflare Worker. JavaScript, despite the extension. Not built by Xcode. |

---

## 2. Source layout

```
LHS Life/
├── LHS-LifeApp.swift          app entry; foreground hooks; notification delegate
├── AppConstants.swift         Worker URL + secret, App Store ID, privacy policy
├── Models/
│   ├── CalendarStore          the central store: events, bell schedules, refresh
│   ├── SchoolEvent            one calendar event + derived facts (category, home game, holiday…)
│   ├── BellSchedule           a day's periods + ScheduleType
│   ├── UserSettings           every preference; iCloud sync for identity, not alerts   [shared]
│   ├── PeriodConfig           a period's name, color, on/off                           [shared]
│   └── ScheduleActivityAttributes  the Live Activity's data contract                   [shared]
├── Services/
│   ├── ICalService / ICalParser        fetch + parse the feed (RFC 5545, no dependencies)
│   ├── BellScheduleParser              bell times from event text (three formats + finals tables)
│   ├── ScheduleImageParser             bell times from a posted PICTURE (Vision OCR)
│   ├── CacheService                    last good feed on disk, for instant launch
│   ├── NotificationService             every local reminder
│   ├── LiveActivityService             start / end / reconnect / preview
│   ├── PushTokenService                register with the Worker; capacity refusals
│   ├── BellTransitionService           on-device fallback push at each bell (BGTask)
│   ├── IssueReporter                   once-a-day problem reports to the Worker
│   ├── EmbeddedWebState                WKWebView lifecycle for the three web tabs
│   ├── RemindersService                homework → Apple Reminders
│   ├── SystemCalendarService           "Save to Calendar" (write-only access)
│   ├── AppIconService                  holiday icons by date
│   ├── ReviewPrompter                  when to ask for a rating
│   └── DataResetService                Delete All Data, including web logins
├── Utilities/
│   ├── ScheduleEngine         pure "what period is it?" function            [shared]
│   ├── BellScheduleDetector   keyword rules: schedule type, holiday, etc.   [shared]
│   ├── PathwaysService, ServeAThonService, ClassOrientationService, APExamService
│   │                          special days that depend on the student's grade
│   ├── SharedStore            App Group bridge to the widget                [shared]
│   ├── ColorPalette, DateHelpers, HapticEngine, LHSLogger, DebugClock
├── AppIntents/                Siri phrases, Shortcuts actions, snippets
├── UI/
│   ├── AppTabContainer        root: picks iPhone or iPad layout; app-wide alerts and cards
│   ├── DesignSystem           every color, font, spacing (LS.*), animation
│   ├── iPhone/                PhoneLayout, PhoneTabDock, PhoneToolbar
│   ├── iPad/                  iPadRootView (NavigationSplitView), iPadSidebar
│   ├── Tabs/                  EventsTabView, MapTabView, thin web-tab wrappers
│   ├── Settings/              SettingsSheetView, PrivacyPolicyView
│   └── Shared/                header pill, banners, cards, sheets, overlays
├── Assets.xcassets            shared with the widget extension
├── IconPreviews.xcassets      app-only; GENERATED at build time (see §10)
└── Resources/PRIVACY.md       shown in the app and linked from the App Store

App Icons/                     the four Icon Composer files (Classic + holidays)
└── Artwork/                   source art (pumpkin, poinsettia, cornucopia); not built
Scripts/render-icon-previews.sh  renders the in-app icon pictures (build phase)
```

`[shared]` files compile into both the app and the widget extension (target
membership is set in the Xcode project). Code that only the app may run is
fenced with `#if !WIDGET_EXTENSION`.

---

## 3. State and observation

- Everything observable uses `@Observable`. Views read exactly the properties
  they use, so a change re-renders only the views that read it.
- `CalendarStore` and `UserSettings` are created once at the `App` level and
  passed down with `.environment(...)`. Each also has a `.shared` instance for
  services, App Intents and the widget — the same object, not a copy.
- Services are `@MainActor` singletons (`LiveActivityService.shared`,
  `AppIconService.shared`, …) or static enums (`NotificationService`,
  `IssueReporter`). Heavy work leaves the main actor explicitly: OCR runs
  `@concurrent`; network calls are `async`.
- Sheets re-inject the environment (`.environment(store)` …) because on macOS a
  sheet doesn't inherit it.

### Settings storage

`UserSettings` lives in the App Group's `UserDefaults` so the widget can read
it. Changes are held in memory and written by `save()`.

**iCloud sync is deliberately partial.** Identity follows the person — class
names and colors, graduation year, sign-in approval. **Alerts stay on each
device** — every reminder toggle and time, ASB days, and Live Activity mode —
because a reminder belongs on the phone in your pocket, not also on the Mac and
the iPad.

**One-time migrations** (`applyFeatureDefaultsOnce`, versioned) let an update
change a default for existing users exactly once — e.g. turning Live Activities
to Every Day — without overriding anyone who changes it back.

---

## 4. Calendar pipeline

```
launch ─► CacheService (instant)      ┐
foreground (30 s floor)               ├─► CalendarStore.refresh()
pull-to-refresh on the day view       ┘
        ICalService.fetch  (one retry after 3 s on a connection problem)
        ICalParser          → [SchoolEvent]
        applyEvents         → bell schedules for every day:
             BellScheduleParser   posted text, in any of its formats
             floor rules          days with no posted times get the standard
                                  schedule for that kind of day
             special days         Pathways, Serve-a-thon, Class Orientation, finals
        applyImageSchedules → days posted as a picture: download, OCR, replace
                              the floor-rule guess with the real bells
        NotificationService → reschedule every reminder from the new data
        SharedStore         → widget copy
        IssueReporter       → only if something the school can fix failed
```

- **Bell schedule formats.** CalendarWiz descriptions arrive as stacked tables
  (one value per line), one-row-per-line text (`8:00 — 8:40 ..... First
  Period`), HTML finals tables covering several days, or just an image.
  `BellScheduleParser.parseAll` returns `[BellSchedule]` because one finals
  event fills in several days.
- **Picture schedules.** `ScheduleImageParser` runs Vision text recognition on
  the CPU, off the main actor. Only floor-rule days are overridden — a real
  posted table always wins. Results are cached per image.
- **Event facts** are derived, not stored: `SchoolEvent` computes category,
  `isHomeGame`, `sport`, a time parsed from the title for "all day" games, and
  `isHoliday` (Schedules-category events only — an event titled "Christmas
  Wreaths" once made a school day a holiday).

---

## 5. Schedule engine

`ScheduleEngine.state(for:schedule:settings:isPathwaysDay:isHoliday:)` is a pure
function: a date, a day's schedule and the student's settings in; a
`ScheduleState` out — `dayState` (`beforeSchool`, `inSession`,
`betweenPeriods`, `afterSchool`, `noSchedule`, `pathwaysDay`, `holiday`), the
current and next slot, progress and time remaining. Disabled periods are
skipped; Break and Lunch always show.

`CalendarStore.todayState(at:)` memoizes the day-level flags (holiday,
Pathways) per day key, so the per-tick cost is just the pure function.

`CalendarStore.schoolDay(on:)` answers "when does school start and end for
this student on this date?" — used by the Shortcuts value actions so a shortcut
and the app can't disagree.

---

## 6. UI structure

`AppTabContainer` branches once on idiom:

```
iPhone: PhoneLayout                         iPad: iPadRootView
  NavigationStack per tab                     NavigationSplitView
  PhoneToolbar: header pill (principal),        iPadSidebar: header pill, capacity
    phone, settings                               banner, tabs, Settings pinned
  PhoneTabDock: native TabView (iOS 26+)        detail: the selected tab + toolbar
    or custom capsule (17–25)
```

App-wide layers on top of either layout: the launch screen, the first-time
capacity alert, the holiday icon card (`AppIconIntroOverlay`), the homework
popup, the easter egg, and the confirmation overlay.

**Header pill** (`ScheduleHeaderPill`): "22 min left in Chemistry" plus a
secondary line. Updates **once a minute, on the minute** — bells land on whole
minutes, so it flips the moment the bell rings — and immediately on foreground.
Debug builds under `-demoClock` tick every second for screen recordings.

**Events tab** (`EventsTabView`): a week strip over a day timeline (periods and
events side by side, up to four overlap columns), with month and year zoom
levels. Pull to refresh on the day view.

**Web tabs**: `EmbeddedWebState` owns each `WKWebView` and its delegate, so
pages keep loading while their tab is hidden. All three start loading at
launch, after the first frame. Insets use `obscuredContentInsets`
(iOS 26) / viewport insets, never `scrollView.contentInset`.

**Settings** (`SettingsSheetView`): a stock grouped `List` — My Info, My
Classes, App Icon (holidays only), Lock Screen, Reminders (rows that push to a
detail screen), ASB, Map, Sign Out, About.

---

## 7. Live Activities

The card is a `ScheduleActivityAttributes` activity. Its **attributes** hold
the whole day's schedule (fixed at start); its **content state** holds only
`slotStartMinutes`, the slot the latest push says is current.

```
foreground ─► LiveActivityService.startIfNeeded
               reconnect to a running card (re-register its token)
               guards: Live Activities allowed, mode allows today
                       (Every Day / Abnormal Days / Off), school left today,
                       app in the foreground
               Activity.request(pushType: .token)
               PushTokenService.register ─► Worker
                    accepted  → the Worker pushes at every bell
                    full      → card ended, capacity alert/banner
               scheduleEndCheck(at: last bell)
```

- **Who moves the card.** The Worker's pushes. iOS does not redraw a Live
  Activity at its own scheduled times — a card cut off from pushes keeps
  showing the last slot. `BellTransitionService` is a best-effort on-device
  fallback (`BGProcessingTask` at each bell).
- **Rendering** (`LHS_WidgetsLiveActivity.swift`): `resolveSlot` prefers the
  pushed slot and falls back to the clock. A `TimelineView(.explicit)` holds a
  date 12 h before the first bell, every start, and the last end — the last end
  stops the card from falling back to the before-school view during the final
  class. Countdowns use `Text(timer:)` and `ProgressView(timerInterval:)`,
  which iOS animates for free.
- **Ending.** The Worker dismisses the card at the last bell. On device,
  `checkSchoolOver` runs at the last bell (if the app is open) and on every
  foreground — never on a timer, which is what once turned a misread holiday
  into a start/end loop.
- **Schedule changes** (a picture finishing OCR, a calendar edit) replace the
  card, but only from the foreground, since a new card can't start from the
  background.
- **Preview.** A frozen sample card (`attributes.preview`, PREVIEW badge) for
  students who don't know what a Live Activity is. It never registers with the
  Worker and is filtered out of every real-card code path
  (`ScheduleActivityAttributes.realActivities`).

---

## 8. Reminders (local notifications)

All scheduled on device by `NotificationService` after each refresh. Each
function clears its own queue first and checks its setting second, so turning
a reminder off also removes what was already queued. iOS allows 64 pending
notifications per app, so lookahead windows are short (about two weeks).

| Reminder | When |
|---|---|
| Professional Dress | Chosen time; noon or later fires the evening before |
| Late Start | Chosen time, same rule; includes the first class time |
| Home Games | Chosen time; includes the student-section theme when posted |
| ASB | Announcements before first period; Student Store before Break and Lunch, on the student's work days |
| Start Live Activity | Morning nudge on days the card should run; cancelled once it starts, never sent to a device the server refused |
| Abnormal schedule | Morning of a non-regular day, only for students with Live Activities off |
| Class Orientation | Before the student's grade-specific orientation window |

---

## 9. The server (Cloudflare Worker)

One file, `APNS Worker.json`, with KV binding `TOKENS` and a cron every minute
Mon–Fri 6 AM–5 PM Pacific. Its header comment documents every page and
variable.

- **Register.** The app sends an anonymous device ID, push token, bell times,
  app build and iOS version. The Worker pushes within two minutes of each bell
  and dismisses at the last one.
- **Capacity.** The phone limit comes from `SUBREQUEST_BUDGET` (default 45 on
  the free plan → 40 phones). Beyond it, the Worker answers "full" with a
  contact, and the app ends the card, shows a one-time alert, then a daily
  dismissible banner.
- **Problem reports.** `IssueReporter` sends a short report at most once per
  device, per problem, per day — only for things the school can fix (calendar
  unreachable, schedule picture unreadable, a school site down, registration
  refused). A student's own bad connection is classed as `network`, not
  `server`. Reports expire after a week.
- **Pages.** `/health`, `/status` (today) and `/status?full=1` (the week, with
  every phone's bell times), `/test-push`, `/purge`, `/rebuild`. Everything but
  `/health` needs `CLIENT_SECRET`.

The Worker URL lives in `AppConstants.workerURL`. Moving the server means
changing it there and shipping an update.

---

## 10. App icons

Classic is the **primary** icon. Holiday icons (Halloween, Thanksgiving,
Christmas) are **alternates**, listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
`AppIconService.holidays` defines each date window; inside a window the App
Icon section appears in Settings and a card offers the icon once per holiday
per year. Switching shows iOS's own confirmation alert — there is no approved
way to switch silently.

**The picker can't show the real icons** — `UIImage(named:)` returns nil for
compiled `.icon` files — so it shows rendered copies. The **Render Icon
Previews** build phase runs `Scripts/render-icon-previews.sh` first in every
build; it re-renders a preview only when its `.icon` changed. It writes to the
app-only `IconPreviews.xcassets` (writing to the shared `Assets.xcassets` would
make the app and widget targets depend on each other), and script sandboxing is
off for the app target so it can read inside `.icon` folders.

**Adding a holiday:** the `.icon` file in `App Icons/` and the app target, its name in the
alternate list, a line in the script's `ICONS` and the phase's inputs and
outputs, and an entry in `AppIconService.holidays`.

---

## 11. Siri and Shortcuts

`LHSAppShortcuts` registers spoken phrases ("What's my next class in LHS
Life?"). Two kinds of intents:

- **Spoken** (`NextClassIntent`, `NextBellIntent`, `TodayScheduleIntent`, …)
  answer with a dialog and a snippet card.
- **Value-returning** (`SchoolDayValueIntents`: start time, end time, schedule
  type, is there school) return a plain `Date`/`String`/`Bool` for automations
  and say nothing.

Navigation intents (`OpenLunchIntent`, …) go through `AppNavigationCoordinator`.

---

## 12. Timers and background work

| What | Cadence | Owner |
|---|---|---|
| Header pill | On each minute (1 s under `-demoClock`) | `ScheduleHeaderPill` |
| Live Activity end check | Last bell + every foreground | `LiveActivityService` |
| Calendar refresh | Launch, foreground (30 s floor), pull | `CalendarStore` |
| Bell pushes | Every minute, school hours | Worker cron |
| On-device bell fallback | One `BGProcessingTask` per bell | `BellTransitionService` |
| Reminder lookahead | ~2 weeks, rebuilt each refresh | `NotificationService` |
| Problem reports | ≤ once per device per problem per day | `IssueReporter` |

---

## 13. Debugging aids

Debug builds only:

| | |
|---|---|
| `-demoClock "yyyy-MM-dd HH:mm"` | Runs the app on a fake, moving clock |
| `-screenshotDemo` | A believable mid-class Live Activity, no server |
| `-simulateServerFull` | Behaves as if the Worker refused this device |
| Settings → Debug | Force header text, start dummy/real/demo cards, simulate full, end cards |

Logging goes through `LHSLogger` (subsystem `lhslife`; categories such as
`liveActivity`, `ical`, `notifications`, `appIcon`). Use `.notice` or `.error`
for anything that must survive into a TestFlight or App Store build's logs.
