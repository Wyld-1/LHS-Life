# LHS Life — App Architecture

## Top-Level Structure

```
LHS Life (app target)
├── Models/
│   ├── SchoolEvent.swift              — iCal event model
│   ├── BellSchedule.swift             — parsed bell schedule + Period type
│   ├── PeriodConfig.swift             — per-period user config (shared with widget)
│   ├── UserSettings.swift             — all preferences (shared with widget)
│   ├── CalendarStore.swift            — central data store, @Observable, @MainActor
│   └── ScheduleActivityAttributes.swift — Live Activity data contract (shared with widget)
├── Services/
│   ├── ICalService.swift              — network fetch of CalendarWiz iCal feed
│   ├── ICalParser.swift               — RFC 5545 parser, zero dependencies
│   ├── BellScheduleParser.swift       — extracts structured periods from iCal description text
│   ├── CacheService.swift             — JSON cache in Caches directory
│   ├── EmbeddedWebState.swift         — WKWebView lifecycle + EmbeddedWebView SwiftUI wrapper
│   ├── RemindersService.swift         — EventKit wrapper for homework reminders
│   ├── NotificationService.swift      — local notification scheduling (dress, ASB)
│   └── LiveActivityService.swift      — ActivityKit lifecycle management
├── Utilities/
│   ├── ScheduleEngine.swift           — pure stateless "what period is it?" engine (shared)
│   ├── SharedStore.swift              — App Group UserDefaults bridge to widgets (shared)
│   ├── ColorPalette.swift             — 10-color palette as hex strings (shared)
│   ├── BellScheduleDetector.swift     — keyword heuristics for event categorization
│   ├── PathwaysService.swift          — graduation year + event keyword logic
│   ├── APExamService.swift            — AP exam day state + settings badge
│   ├── ClassOrientationService.swift  — class orientation logic
│   ├── DateHelpers.swift              — shared date formatters
│   ├── DebugClock.swift               — forced date/time override for testing
│   ├── LHSLogger.swift                — os.Logger wrappers, subsystem "lhslife"
│   └── HapticEngine.swift             — centralized UIImpactFeedbackGenerator wrapper
└── UI/
    ├── DesignSystem.swift             — all colors, fonts, spacing, animations, modifiers
    ├── AppTabContainer.swift          — root container; branches iPhone vs iPad
    ├── AccessGuardView.swift          — access gate
    ├── HomeworkPopup.swift            — floating homework entry card
    ├── LaunchScreen.swift             — startup loading screen
    ├── ContentView.swift              — entry point view, hosts AppTabContainer
    ├── iPhone/
    │   ├── PhoneLayout.swift          — iPhone root: AppDock + popup/launch overlays
    │   ├── PhoneTabDock.swift         — tab switcher, iOS 26 / legacy branch
    │   └── PhoneToolbar.swift         — native nav bar (principal pill + trailing buttons)
    ├── iPad/
    │   ├── iPadRootView.swift         — NavigationSplitView root + detail toolbar
    │   └── iPadSidebar.swift          — Today module, nav rows, pinned Settings
    ├── Shared/
    │   ├── ScheduleHeaderPill.swift   — schedule pill + 1s timer (nav bar / sidebar)
    │   ├── ToolbarCapsule.swift       — DELETED (both platforms use native toolbars)
    │   ├── APExamBanner.swift         — AP exam day banner
    │   ├── EventDetailSheet.swift     — event detail presentation
    │   └── HomeworkFAB.swift          — floating homework button (pre-26 iPhone)
    ├── Tabs/
    │   ├── EventsTabView.swift        — merged Today + Calendar tab (Day/Month/Year)
    │   ├── LunchTabView.swift         — thin wrapper over EmbeddedWebView
    │   ├── PowerSchoolTabView.swift   — thin wrapper over EmbeddedWebView
    │   └── SchoologyTabView.swift     — thin wrapper over EmbeddedWebView
    └── Settings/
        └── SettingsSheetView.swift    — settings sheet, all options in one scroll view

LHS Widgets (widget extension target)
├── LHS_WidgetsBundle.swift            — @main WidgetBundle
├── LHS_WidgetsLiveActivity.swift      — ActivityConfiguration for Dynamic Island + lock screen
├── LHS_Widgets.swift                  — lock screen / home screen widgets (stub)
└── LHS_WidgetsControl.swift           — control widget (stub)

Shared files (added to both targets):
    Models/PeriodConfig.swift
    Models/UserSettings.swift
    Models/ScheduleActivityAttributes.swift
    Utilities/ScheduleEngine.swift
    Utilities/SharedStore.swift
    Utilities/ColorPalette.swift
```

---

## Observation Model

The app uses the `@Observable` macro (iOS 17+, `Observation` framework) throughout. This replaces `ObservableObject` + `@Published`.

**Why:** With `ObservableObject`, any view holding `@EnvironmentObject` re-renders when any published property changes. With `@Observable`, SwiftUI tracks exactly which properties each view body reads, and only re-renders that view when those specific properties change. The header timer ticks every second — with the old model this would re-render every view in the app. With `@Observable` it re-renders only `ScheduleHeaderPill`.

**Ownership pattern:**
- `CalendarStore` and `UserSettings` are created once in `LaSalle_ScheduleApp` using `@State` at the `App` level (safe — `App` is never rebuilt by SwiftUI).
- Both are passed into the environment via `.environment(store)` / `.environment(settings)` (not `.environmentObject`).
- Views read them via `@Environment(CalendarStore.self)`.
- Views that need bindings use `@Bindable var settings = settings` inside the view body, or accept `@Bindable` as a parameter (as in `SettingsSheetView`).
- `UserSettings.shared` is a singleton for access from non-SwiftUI code (services, widgets). The same instance is passed into the environment.

---

## Data Flow: Calendar Events

```
CalendarWiz iCal feed (HTTPS)
    ↓  ICalService.fetchEvents()         — URLSession, async
    ↓  ICalParser.parse()                — RFC 5545, pure Swift, no dependencies
    →  [SchoolEvent]
    ↓  BellScheduleParser.parse()        — extracts structured periods from description text
    →  [String: BellSchedule]            — keyed by "yyyy-MM-dd"
    ↓  CacheService.saveEvents()         — JSON → Caches directory
    ↓  SharedStore.write()               — JSON → App Group UserDefaults
    →  CalendarStore.events              — @Observable, drives all views
    →  CalendarStore.bellSchedules       — @Observable, drives schedule engine
```

On app launch, `CalendarStore.loadAll()` first reads from `CacheService` (synchronous, instant) to populate the UI, then fetches fresh data from the network. Views always see data immediately; they silently update when the fetch completes.

**Bell schedule parsing:** The iCal `DESCRIPTION` field for schedule events contains a plain-text table with one value per line in groups of four (period name, start time, end time, duration). `BellScheduleParser` finds the `"Period"` header line and consumes groups of four lines after it. No regex — pure line-by-line parsing.

---

## Data Flow: Settings

`UserSettings` reads from `UserDefaults(suiteName: "group.lasalle.widgetinfo")` exactly once in `init()`. All properties are stored in memory. `save()` writes all properties to UserDefaults in one call, triggered only on settings sheet dismiss (`onDisappear`). No disk I/O during user interaction.

The App Group suite (`group.lasalle.widgetinfo`) is used for all UserDefaults reads and writes so the widget extension can read settings (period names, colors, enabled state) without any IPC or network call.

**Palette version:** `UserSettings` stores a `paletteVersion` integer. If the stored version doesn't match `currentPaletteVersion` (currently 2), `periodConfigs` is reset to defaults. This handles palette reordering without corrupting stored color indices.

---

## Schedule Engine

`ScheduleEngine` is a pure stateless enum — all methods are static, all inputs are parameters, no stored state. It is shared between the app target and the widget extension.

Given a `BellSchedule`, `UserSettings`, current `Date`, and flags (`isPathwaysDay`, `isHoliday`), it returns a `ScheduleState` containing:
- `currentSlot: ActiveSlot?` — the period currently in progress
- `nextSlot: ActiveSlot?` — the next period
- `dayState: DayState` — one of: `.beforeSchool`, `.inSession`, `.betweenPeriods`, `.afterSchool`, `.noSchedule`, `.pathwaysDay`, `.holiday`

`ActiveSlot` contains the `Period`, its `PeriodConfig` (for display name and color), start/end dates, and computed `progress` (0–1) and `timeRemaining`.

**Memoization:** `CalendarStore.todayState()` caches the day's holiday and Pathways flags by day key. The expensive array scans (checking all events for holiday/Pathways keywords) run once per calendar day, not once per second. The 1-second timer calls `todayState()` which re-runs `ScheduleEngine.state()` — a cheap pure function — but skips the event scans.

---

## UI Structure

### AppTabContainer — platform branch

`AppTabContainer` picks `PhoneLayout` or `iPadRootView` by idiom. Both platforms
now use **native toolbars** — there is no floating header layer on either.

```
PhoneLayout                                iPadRootView
└── ZStack                                 └── ZStack
    ├── AppDock (tabs + content)               ├── NavigationSplitView
    ├── HomeworkFAB (pre-26 only)              │   ├── iPadSidebar
    ├── HomeworkPopup   [zIndex 10]            │   └── detail + .toolbar
    └── LaunchScreen    [zIndex 20]            ├── HomeworkPopup   [zIndex 10]
                                               └── LaunchScreen    [zIndex 20]
```

### Toolbars

Each iPhone tab wraps its content in its own `NavigationStack` and applies
`.phoneToolbar(tab:config:)` (`PhoneToolbar.swift`):

- `.principal` — `ScheduleHeaderPill(suppressGlass: true)`, fixed 44pt height.
- `.topBarTrailing` — contextual button (zoom-out in Events, back in the web
  tabs, none in Lunch) tinted `lsPrimary`, plus the settings button tinted
  `lsBlue` with its AP badge overlay.

`PhoneToolbarConfig` carries the actions; it is built in `PhoneLayout` (which
has the store/settings/calendarUI dependencies) and passed down through
`AppDock` to each tab.

**`suppressGlass` matters:** a toolbar item already sits on the system's own
material. `ScheduleHeaderPill` self-applies glass (iOS 26) or a frosted capsule
(pre-26) when standalone, so both are suppressed inside a toolbar to avoid
double-applied material. Same reason iPad renders its toolbar button plain.

iPad uses `navigationTitle` + `.toolbar` directly in `iPadRootView`; its
schedule pill lives in `iPadSidebar`, not the toolbar.

### AppDock

`AppDock` is the single point of branching between iOS versions for tab content:

```
AppDock
├── if iOS 26+: SystemTabDock
│   └── TabView (native, liquid glass)
│       ├── Events, Lunch, Grades, Schoology tabs (each in a NavigationStack)
│       ├── .tabBarMinimizeBehavior(.onScrollDown) in Day view
│       └── .tabViewBottomAccessory — HomeworkAccessory
└── else: LegacyTabDock
    ├── ZStack of all four tab views (opacity-switched)
    └── LegacyDockBar (frosted capsule, bottom-left)
```

**Opacity switching (legacy):** All four tab views are always mounted in the ZStack. They are shown/hidden by `.opacity()` and `.allowsHitTesting()`. This keeps `WKWebView` instances alive across tab switches. Removing and re-adding a view would destroy and recreate the web view, losing page state.

**Same-tab-tap home:** Both docks detect a tap on the already-selected tab and
call `onSameTabTap(tab)` instead of changing selection. `PhoneLayout` /
`iPadRootView` handle it: Events jumps to today, the three web tabs `.reload()`.

**Homework tab interception:** `AppTabContainer` observes `selectedTab` via `.onChange`. When it becomes `.homework`, it immediately sets `selectedTab = previousTab` (before SwiftUI renders the homework view) and sets `showHomework = true`. The content view never changes; the popup appears over whatever tab was active.

---

## Web View Architecture

All three embedded web views (Lunch, PowerSchool, Schoology) use `EmbeddedWebState`, an `@Observable` class that owns the `WKWebView` and its navigation delegate.

**Initialization:** `AppTabContainer.task` calls `lunchState.initialize()`, `powerschoolState.initialize()`, and `schoologyState.initialize()` in parallel using `async let`. Each `initialize()` creates the `WKWebView` and fires `load()`. This runs after the first frame renders, so it never blocks layout.

**Delegate ownership:** The `WKNavigationDelegate` (`EmbeddedWebDelegate`) is a stored property on `EmbeddedWebState`, not created inside `UIViewRepresentable.makeCoordinator()`. This is critical: `makeUIView` only runs when the view is visible. During opacity-switching, invisible tab views never call `makeUIView`. If the delegate were created there, navigation callbacks would be lost while the tab is hidden. With the delegate owned by the state object, callbacks fire regardless of view visibility.

**Mobile user agent:** All web views use a Mobile Safari user agent string, forcing Schoology and PowerSchool to serve their mobile-responsive layouts.

**Dark CSS (Lunch only):** A `WKUserScript` injected at `documentEnd` applies `!important` CSS overrides to force white text and dark backgrounds matching the app's color scheme.

**Content insets — obscuredContentInsets, not contentInset:**

`WKWebView` derives its layout viewport from its **frame** and ignores
`scrollView.contentInset` entirely. Setting `contentInset` therefore creates a
region WebKit knows nothing about: `contentSize` stays inflated by the inset
height (a dead band you can scroll into with no content in it), and WebKit's
notion of "scrolled to top" (offset 0) permanently disagrees with the app's
(offset `-inset`). Any correction applied after the fact loses, because WebKit
re-derives position from its own model on every reflow — and reflows are
asynchronous and out-of-process, landing after the SwiftUI update pass.

The current implementation states the obscured region once, declaratively:

```
initialize()
    → applyObscuredInsets(to:)      — BEFORE load()
        iOS 26+ : wv.obscuredContentInsets = insets
        iOS 16+ : wv.setMinimumViewportInset(_:maximumViewportInset:)
        + verticalScrollIndicatorInsets (indicator geometry is separate)
    → scrollView.contentInsetAdjustmentBehavior = .always
```

Both halves are required. `obscuredContentInsets` fixes the **layout viewport**;
`.always` lets UIKit adjust the **scroll view's** resting position to match.
With `.never` ("do not adjust the scroll view insets") the scroll view clamps at
offset 0 — content parks behind the toolbar, refuses to be pulled down, and
snaps back on any scroll attempt.

**Per-idiom inset:** iPhone uses `LS.contentTopInset` (the floating toolbar
overlays content). iPad uses **0** — the `NavigationSplitView` detail column
already lays the web view out below its nav bar, so an inset there is pure
phantom scroll space.

**Frame ownership:** `translatesAutoresizingMaskIntoConstraints` is left at its
UIKit default (`true`). Setting it `false` zeroes the frame the moment it's
applied, causing the first page to load into a 0×0 viewport and reflow on first
mount. `updateUIView` assigns `frame` explicitly from `GeometryReader`, which is
what sizes the view for iPad's narrower detail column.

---

## App Group and Widget Data Flow

App Group ID: `group.lasalle.widgetinfo`

```
App (writes)                    Widget Extension (reads)
────────────────                ────────────────────────
UserSettings.save()         →   UserDefaults(suiteName:)
SharedStore.write()         →   SharedStore.read*()
  events: JSON blob              Used by lock screen widgets
  bellSchedules: JSON blob       Used by Live Activity (via ScheduleEngine)
```

`SharedStore` is a simple enum with static read/write methods. It JSON-encodes `[SchoolEvent]` and `[String: BellSchedule]` into the App Group UserDefaults. Widgets read from this store directly — they never touch the network or parse iCal.

---

## Live Activity Lifecycle

`LiveActivityService` is a `@MainActor` singleton driven by the 1-second header timer.

```
ScheduleHeaderPill timer (1s)
    → LiveActivityService.update(state:settings:)
        if liveActivityEnabled == false → end()
        if dayState is school hours:
            if no current activity → start()
            else → updateContent() [throttled to 30s]
        if dayState is after school → end()
```

**Throttling:** `ActivityKit` rate-limits updates. `LiveActivityService` tracks when it last called `activity.update()` and skips calls that come sooner than 30 seconds after the last one. The 1-second timer drives the check but the actual ActivityKit call fires at most every 30 seconds.

**Color:** The Live Activity uses the period color hex from the current slot's `PeriodConfig`. Since `ScheduleActivityAttributes` is static (set at start), the color is set at activity creation time and is the color of the period that was active when school started. Updating the color requires ending and restarting the activity.

**Widget UI:** Defined in `LHS_WidgetsLiveActivity.swift` using `ActivityConfiguration(for: ScheduleActivityAttributes.self)`. The widget renders four Dynamic Island presentations (compact leading, compact trailing, minimal, expanded) and a lock screen banner view.

---

## Notification Scheduling

All notifications are scheduled by `NotificationService` (a static enum) from within `CalendarStore.refresh()`, which runs at app launch and on manual refresh.

**Professional dress:** Scans all fetched events for dress-related keywords in title/description. For each match, schedules a `UNCalendarNotificationTrigger` firing at 9:00 PM the evening before. Old notifications are cleared before rescheduling.

**ASB notifications:** Runs only when `settings.isASBMember == true`. Clears all `asb-*` identifiers from pending notifications, then iterates the next 14 calendar days. For each day that is a weekday, has a bell schedule, and matches one of the user's configured work days:
- Announcement: 10 minutes before the first period's start time. `userInfo["url"] = "teamreach://"` — tapping opens TeamReach.
- Break: 5 minutes before the Break period's start time.
- Lunch: 5 minutes before the Lunch period's start time.

`UNUserNotificationCenter.delegate` is set to `NotificationDelegate.shared` at app launch. This handles foreground notification display (`.banner`, `.sound`) and deep-link handling (opens `teamreach://` URL on announcement tap).

---

## Timing and Background Behavior

| Timer | Owner | Interval | Purpose |
|---|---|---|---|
| Header timer | `ScheduleHeaderPill.onAppear` | 1 second | Updates `now`, drives pill text and progress, calls `LiveActivityService.update()` |
| LiveActivity update | `LiveActivityService` | 30 seconds | Calls `Activity.update()` — stays within ActivityKit rate limit |
| ASB notification window | `NotificationService` | 14 days lookahead | How far ahead ASB notifications are pre-scheduled on each refresh |

The app does not use `BGAppRefreshTask` or background URL sessions. All network activity happens in the foreground when the app is open.

---

## Haptic Engine

`HapticEngine.shared` is a `@MainActor` singleton. It owns four pre-initialized `UIFeedbackGenerator` instances:
- `UIImpactFeedbackGenerator(style: .light)` — `tap()`
- `UIImpactFeedbackGenerator(style: .medium)` — `bump()`
- `UISelectionFeedbackGenerator` — `tick()`
- `UINotificationFeedbackGenerator` — `success()`

`prepare()` is called on all four at app launch (`App.init`). After each fire, `prepare()` is called again to keep the Taptic Engine warm. This eliminates the cold-start delay on first use.

---

## Pre-warming Strategy

Several components are pre-rendered at zero opacity in `AppTabContainer`'s `.background` modifier to eliminate first-open latency:

| Component | Pre-warm target |
|---|---|
| `SettingsSheetView` | SwiftUI view tree: 9 PeriodRows, toggles, all @State |
| `ColorPickerPrewarm` | `TextField` with `@FocusState`, `.popover` presentation machinery |

Web views are initialized via `.task` (not pre-rendered as views), which fires after the first frame. This avoids blocking layout while still starting the network requests as early as possible.
