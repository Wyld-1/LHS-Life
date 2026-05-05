# LHS Life — Design Requirements & Feature Specification

## Overview

LHS Life is the all-in-one companion app for La Salle High School (Yakima, WA). It is used daily by students and teachers to track the bell schedule, view school events, order lunch, access grades (PowerSchool), and manage assignments (Schoology). The app is designed to be opened many times per day — before class, between periods, at lunch — so every interaction must be instantaneous and require minimal deliberate navigation.

Primary users: La Salle students on school-issued iPads and personal iPhones.
Secondary users: Teachers and staff.

---

## Design Requirements

These requirements govern every feature, screen, and update to the app. A change that violates any requirement must be revised before shipping.

### Responsiveness
- Every tap must produce a visible response within one frame (16ms). No button may feel unresponsive.
- All heavy work (networking, parsing, web view initialization, notification scheduling) runs off the main thread or is deferred to after the first frame renders.
- UI state that changes frequently (the header countdown, the progress bar) updates on a 1-second timer without triggering re-renders in unrelated views.
- Settings changes are held in memory and flushed to disk once on sheet dismiss — never on every individual interaction.

### Glanceability
- The most important information (current period, time remaining) is visible without opening the app, via the Dynamic Island Live Activity and lock screen widget.
- Inside the app, the floating header pill answers "what period is it and how much time is left" without any scrolling or tapping.
- The header secondary line surfaces the next relevant event or period so a student never needs to navigate to find what's next.

### Intuitiveness
- Every navigation action has at most one tap from anywhere in the app.
- The homework entry flow requires no navigation — a floating button opens a popup over the current view, auto-focuses the text field, and auto-selects the current class.
- Tapping an already-active tab navigates that tab's web view back to its home URL.
- The settings sheet shows all configurable options in a single scroll view with no submenus or navigation pushes.

### Frictionlessness
- All web views (Lunch, PowerSchool, Schoology) begin loading at app launch, before the user taps any tab. By the time a tab is tapped, content is already loaded.
- A launch screen blocks interaction only for the duration of the actual load, then disappears automatically.
- Keyboard appears immediately when a text field becomes relevant (homework popup on open, period name edit on tap, grad year edit on tap).
- Date and class selection in the homework popup use native system menus — no custom picker screens, no extra navigation.

### Personalization
- Every period slot (0–8) has a user-configurable name, color, and enabled/disabled toggle.
- The app respects which periods a student actually has and hides disabled periods from all schedule displays.
- ASB members can configure their work days and receive reminders specific to their Student Store schedule.
- Pathways Day eligibility is derived automatically from the student's graduation year.

### Platform Fidelity
- On iOS 26+, the tab bar uses the native system liquid glass TabView with `.tabBarMinimizeBehavior(.onScrollDown)`. On iOS 17–25, a custom frosted-glass capsule is used. Both are implemented in `AppDock` — `AppTabContainer` has zero `#available` checks.
- On iOS 26+, the homework button is the system `.search` role tab (detached circle). On iOS 17–25, a floating `HomeworkFAB` circle is positioned at the bottom-right.
- Glass effects (`glassEffect()`) are applied on iOS 26+ and fall back to `ultraThinMaterial` on earlier versions.
- The app targets iOS 17+ and must compile and run correctly on all versions from 17 through the current release.

### Maintainability
- All visual constants (colors, fonts, spacing, corner radii, animations) are defined in `DesignSystem.swift`. No magic numbers appear in view files.
- OS-version branching is isolated to the component that needs it (`AppDock`, `WebNavButtons`, `ScheduleHeader`). Container views are version-agnostic.
- Files shared between the app and widget extension are marked with a comment indicating both targets. No shared file imports UIKit or SwiftUI.
- Settings are never written to disk during user interaction — only on explicit save.

---

## Feature Specification

### Header Pill

A floating pill visible at the top of every tab. Never hidden.

- **Primary text** — during school: "42 min left in Chemistry" / "English in 3 min". Before school: "School in 12 min" or "School at 8:00 AM". After school / weekend: day-appropriate text ("Happy Friday 🎉", "Enjoy the weekend!").
- **Secondary text** — during school: "Next: Lunch at 11:45 AM". After school / before school on weekdays: the next upcoming home event (e.g. "Prom: tomorrow @ 7:30 PM"). On Saturday: today's events only. On Sunday: today's then Monday's events.
- **Progress fill** — a color wash inside the pill grows left-to-right as the current period progresses. Color matches the period's assigned color.
- **Settings button** — person icon at the right of the header. Opens the settings sheet.
- **Event filtering** — only home athletic events (location contains "lasalle", "la salle", "marquette", "lhs", or "home") are shown. Away athletic events are always excluded. Non-athletic events (prom, mass, assemblies) always show regardless of location.
- **Update cadence** — 1-second `Timer` in `ScheduleHeader`. The timer also drives `LiveActivityService` which throttles ActivityKit calls to every 30 seconds.

### Events Tab

The default landing tab. Bell schedule and school events.

- Shows today's bell schedule as a vertical timeline (current, past, future periods).
- Shows today's school events below the schedule.
- Scrollable. Content scrolls behind the floating header; a gradient blends the top of the content into the app background color.
- Calendar view for browsing upcoming events — accessible by scrolling up or via a control within the tab.
- Schedule type badge ("Regular", "Block", "Late Start", etc.) derived from the bell schedule event.

### Lunch Tab (Order)

Embeds `https://lhs.plan.tech/lunch/` in a WKWebView.

- Dark CSS injected at document load to invert background and text colors to match the app's dark theme.
- Mobile user agent set to force the mobile-responsive layout.
- Top gradient blends the page into the app background under the header.
- Loads at app launch in the background. The tab reveals an already-loaded page.

### Grades Tab (PowerSchool)

Embeds `https://lasalleyakima.powerschool.com/guardian/home.html?_userTypeHint=student#` in a WKWebView.

- Mobile user agent set to force the mobile-responsive layout.
- Top gradient blends the page into the app background.
- Web navigation buttons (Home, Back) visible at the bottom-right of the screen.
- Tapping the Grades tab when already on it reloads the page to the home URL.
- Loads at app launch in the background.

### Schoology Tab

Embeds `https://lasalleyakima.schoology.com/home` in a WKWebView.

- Mobile user agent set to force the mobile-responsive layout.
- Top gradient blends the page into the app background.
- Web navigation buttons (Home, Back) visible at the bottom-right of the screen.
- Tapping the Schoology tab when already on it reloads the page to the home URL.
- Loads at app launch in the background.

### Homework Popup

A centered card floating over the current tab. The tab beneath remains fully visible.

- Triggered by: the homework FAB (iOS 17–25), or the checklist tab (iOS 26+).
- On iOS 26+, tapping the homework tab snaps `selectedTab` back to the previous tab before any render occurs, so the content view never switches.
- **Text field** — auto-focused on open. Submit via keyboard return key.
- **Class selector** — native `Menu` wrapping a `Picker`. Defaults to the currently active period (`ScheduleEngine.currentSlot`), or the next period if between periods, or the first enabled period if outside school hours.
- **Date selector** — native `Menu` with options: Tomorrow (next calendar day), Next Monday (always the coming Monday, never same-day even if today is Monday), Pick a Date (opens an inline `DatePicker` inside the card), Remove Date (appears only when a date is set).
- **Save** — creates a reminder in Apple Reminders in a list named after the selected class. Requires Reminders authorization.
- **Cancel / tap scrim** — dismisses without saving.
- Popup position is fixed. `.ignoresSafeArea(.keyboard)` prevents it from moving when the keyboard appears.

### Settings Sheet

A system `.sheet` with `presentationDragIndicator(.visible)`. All settings visible in one scroll view — no submenus.

#### My Info section
- **Graduation Year** — displayed as a tappable year value. Tap opens an inline text field with immediate keyboard focus. Used to determine Pathways Day eligibility.
- **ASB Member toggle** — when enabled, reveals a Mon–Fri day selector (five pill buttons). Selected days receive ASB-specific notifications.

#### My Classes section
- Periods 0–8, each as a row with:
  - Period number label
  - Color circle (tap opens a 10-color grid popover)
  - Period name (tap opens an inline text field with immediate keyboard focus)
  - Enabled/disabled toggle
- Defaults: periods 0 and 8 are off. Periods 1–7 are on.
- Default colors (rainbow order): 0=Slate, 1=Coral, 2=Peach, 3=Gold, 4=Mint, 5=Sky, 6=LaSalle Blue, 7=Lavender, 8=Slate.

#### Alerts section
- **Professional Dress** toggle — default on. Sends a notification at 9 PM the evening before any professional dress event.
- **Live Activity** toggle — default off. Enables the Dynamic Island Live Activity during school hours.

- All settings are held in memory during the sheet session. `UserSettings.save()` is called once: on `onDisappear` (covers both swipe-down and Done button dismissal).
- Settings sheet and color picker popover are pre-rendered at zero opacity at app launch to eliminate first-open latency.

### Notifications

All notifications are local (no push server). All use `.default` sound. Haptics fire per user's system notification settings.

| Notification | Trigger | Content |
|---|---|---|
| Professional Dress | 9 PM evening before | "Professional Dress Tomorrow — LaSalle requires professional dress for [event] tomorrow." |
| ASB Announcement | 10 min before first period on work days | "Announcement Time — School starts in 10 minutes. Time to do announcements!" — deep link opens TeamReach app |
| ASB Break | 5 min before Break starts on work days | "Head to Student Store — Break starts in 5 minutes." |
| ASB Lunch | 5 min before Lunch starts on work days | "Head to Student Store — Lunch starts in 5 minutes." |

- Professional dress keywords: "professional dress", "formal dress", "mass attire", "dress uniform", "professional attire", "formal attire".
- ASB notifications are scheduled for the next 14 days on each refresh, replacing any previously scheduled ASB notifications.
- Notifications require `UNUserNotificationCenter` authorization. Requested on first relevant action.
- `NSUserNotificationAlertStyle` is set to `alert` so notifications persist until dismissed.

### Live Activity / Dynamic Island

Requires `liveActivityEnabled = true` in settings. Uses `ActivityKit` + `WidgetKit`.

- **Compact leading** — period color dot.
- **Compact trailing** — time remaining (e.g. "30m 47s") in monospaced font.
- **Minimal** — circular progress arc in period color.
- **Expanded** — period name + color dot (leading), time remaining (trailing), progress bar + next period name (bottom).
- **Lock screen banner** — period name, time remaining, progress bar, next period.
- Starts automatically when school is in session (`.inSession`, `.betweenPeriods`, `.beforeSchool`). Ends when school is over.
- `LiveActivityService` is driven by the same 1-second timer as the header. It throttles actual `Activity.update()` calls to every 30 seconds to stay within ActivityKit rate limits.
- `NSSupportsLiveActivities` and `NSSupportsLiveActivitiesFrequentUpdates` are set in Info.plist.

### Launch Screen

Shown on first launch while all three web views are loading.

- Displays the LHS Life wordmark and a progress bar.
- Progress: calendar events loaded = 34%, each of the three web states ready = 22% each (total = 100%).
- Automatically dismissed with a fade when all states are ready.
- Blocks all interaction while visible. The app is not usable until dismissed.

### Color Palette

10 curated colors, rainbow-ordered, safe on dark backgrounds:

| Index | Name | Hex |
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

### Haptic Feedback

All haptics go through `HapticEngine.shared`, which is warmed at app launch via `prepare()`.

| Event | Method |
|---|---|
| Tab switch, toggle, button press | `tap()` — light impact |
| Homework FAB, confirmations | `bump()` — medium impact |
| Color selection, class selection, period name edit | `tick()` — selection changed |
| Homework saved successfully | `success()` — notification success |

### Pathways Day

When the student's graduation year indicates they are a current junior or senior, and a school event with "pathways" in the title or description exists for the current day, the schedule state is set to `.pathwaysDay`. The header shows "Internship Day". No bell schedule is displayed.
