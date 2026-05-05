# LHS Life — Test Suite Specification

This document specifies tests for Claude Code to implement and run. All tests are `XCTestCase` unit tests targeting the `LHS LifeTests` target. No UI, no simulator, no network. Every test exercises a pure function or a deterministic transformation with controlled inputs.

---

## Setup Instructions for Claude Code

1. Open `LHS LifeTests/` — the test target already exists in the project.
2. Create one file per test class listed below.
3. Run with `xcodebuild test -scheme "LHS Life" -destination "platform=iOS Simulator,name=iPhone 16"`.
4. All tests must pass before any feature work proceeds.

---

## Shared Test Helpers

Create `LHS LifeTests/TestHelpers.swift` added to the test target only.

```swift
import Foundation
@testable import LHS_Life

// MARK: - Date construction

/// Builds a Date for a specific time on a specific day using Pacific time.
/// Use this everywhere instead of Date() so tests are not time-dependent.
func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return cal.date(from: comps)!
}

// MARK: - Bell schedule construction

/// Builds a Period with the given name and start/end times (24h hour/minute).
func makePeriod(id: String = "test", name: String, startH: Int, startM: Int, endH: Int, endM: Int) -> Period {
    var start = DateComponents(); start.hour = startH; start.minute = startM
    var end   = DateComponents(); end.hour   = endH;   end.minute   = endM
    return Period(id: id, name: name, startTime: start, endTime: end)
}

/// Builds a BellSchedule on the given date with the provided periods.
func makeSchedule(on date: Date, periods: [Period], type: ScheduleType = .regular) -> BellSchedule {
    BellSchedule(id: "test-schedule", date: date, scheduleType: type,
                 periods: periods, sourceEventID: "test-event")
}

/// Builds a UserSettings with all periods 1–7 enabled and default names.
/// Periods 0 and 8 disabled. No custom names.
func makeDefaultSettings() -> UserSettings {
    UserSettings()
}

/// Builds a minimal SchoolEvent.
func makeEvent(
    id: String = "evt-1",
    title: String,
    startDate: Date,
    endDate: Date? = nil,
    isAllDay: Bool = false,
    location: String? = nil,
    description: String? = nil,
    category: EventCategory = .other
) -> SchoolEvent {
    SchoolEvent(id: id, title: title, startDate: startDate,
                endDate: endDate ?? startDate, isAllDay: isAllDay,
                location: location, description: description,
                url: nil, category: category)
}
```

---

## 1. ScheduleEngineTests

File: `LHS LifeTests/ScheduleEngineTests.swift`

These are the most critical tests in the suite. `ScheduleEngine.state()` is a pure function — given a date, a schedule, and settings, it returns a deterministic `ScheduleState`. Every branch must be covered.

All tests use a fixed reference schedule representing a standard LaSalle day:
- Period 1: 8:00–8:50
- Break:    9:45–9:55
- Period 2: 8:55–9:45
- Period 3: 10:00–10:50
- Period 4: 10:55–11:45
- Lunch:    11:45–12:15
- Period 5: 12:20–13:10
- Period 6: 13:15–14:05
- Period 7: 14:10–15:00

Reference date: 2026-05-05 (Tuesday). All time inputs are Pacific.

### 1.1 Holiday override
- Input: `isHoliday = true`, any schedule, any date
- Assert: `dayState == .holiday`, `currentSlot == nil`, `nextSlot == nil`

### 1.2 Pathways Day override
- Input: `isPathwaysDay = true`, any schedule, any date
- Assert: `dayState == .pathwaysDay`, `currentSlot == nil`, `nextSlot == nil`

### 1.3 No schedule
- Input: `schedule = nil`, `isHoliday = false`, `isPathwaysDay = false`
- Assert: `dayState == .noSchedule`, `currentSlot == nil`, `nextSlot == nil`

### 1.4 Before school
- Input: date = 2026-05-05 07:30 (before Period 1 starts at 8:00)
- Assert: `dayState == .beforeSchool`, `currentSlot == nil`, `nextSlot?.period.name == "Period 1"`

### 1.5 Exactly at period start
- Input: date = 2026-05-05 08:00:00 (Period 1 start time exactly)
- Assert: `dayState == .inSession`, `currentSlot?.period.name == "Period 1"`

### 1.6 Mid-period
- Input: date = 2026-05-05 08:25 (mid Period 1)
- Assert: `dayState == .inSession`, `currentSlot?.period.name == "Period 1"`, `nextSlot?.period.name == "Break"`

### 1.7 Exactly at period end
- Input: date = 2026-05-05 08:50:00 (Period 1 end time exactly)
- Assert: `dayState == .inSession`, `currentSlot?.period.name == "Period 1"`

### 1.8 Between periods (passing time)
- Input: date = 2026-05-05 08:51 (1 min after Period 1 ends, before Period 2 starts at 8:55)
- Assert: `dayState == .betweenPeriods`, `currentSlot == nil`, `nextSlot?.period.name == "Period 2"`

### 1.9 During Break
- Input: date = 2026-05-05 09:48 (mid Break)
- Assert: `dayState == .inSession`, `currentSlot?.period.name == "Break"`

### 1.10 During Lunch
- Input: date = 2026-05-05 12:00 (mid Lunch)
- Assert: `dayState == .inSession`, `currentSlot?.period.name == "Lunch"`

### 1.11 After last period
- Input: date = 2026-05-05 15:01 (after Period 7 ends at 15:00)
- Assert: `dayState == .afterSchool`, `currentSlot == nil`, `nextSlot == nil`

### 1.12 Last period has no next slot
- Input: date = 2026-05-05 14:30 (mid Period 7)
- Assert: `currentSlot?.period.name == "Period 7"`, `nextSlot == nil`

### 1.13 Disabled period is skipped
- Create settings with Period 1 disabled.
- Input: date = 2026-05-05 08:25 (would be mid Period 1)
- Assert: `dayState == .beforeSchool` (Period 1 skipped, next is Period 2 at 8:55), or `dayState == .betweenPeriods`

### 1.14 Period progress is clamped to [0, 1]
- Input: date = 2026-05-05 08:00 (Period 1 just started)
- Assert: `currentSlot?.progress >= 0.0 && currentSlot?.progress <= 1.0`
- Input: date = 2026-05-05 08:50 (Period 1 just ending)
- Assert: `currentSlot?.progress >= 0.0 && currentSlot?.progress <= 1.0`

### 1.15 Period duration is positive
- For any `currentSlot`, assert: `currentSlot?.duration > 0`

### 1.16 Display name uses custom name when set
- Create settings with Period 1 named "Chemistry".
- Input: date = 2026-05-05 08:25
- Assert: `currentSlot?.displayName == "Chemistry"`

### 1.17 Display name falls back to period name
- Create settings with Period 1 custom name = "" (empty).
- Input: date = 2026-05-05 08:25
- Assert: `currentSlot?.displayName == "Period 1"`

### 1.18 Break and Lunch are visible even when not in PeriodConfig
- Settings only configure periods 0–8. Break and Lunch have no config entry.
- Assert: `currentSlot?.config == nil` during Break/Lunch
- Assert: `currentSlot?.period.name == "Break"` / `"Lunch"` (not filtered out)

---

## 2. ScheduleEngineHeaderTextTests

File: `LHS LifeTests/ScheduleEngineHeaderTextTests.swift`

Tests `ScheduleEngine.headerPrimaryText(for:)`. These tests must use a mock `ScheduleState` constructed directly (not via `ScheduleEngine.state()`), since `headerPrimaryText` only receives the state struct.

**Note:** `headerPrimaryText` reads `Date()` internally for the `.betweenPeriods` and `.beforeSchool` cases. Tests for those cases should verify the output format rather than exact minute counts, since `Date()` is not injectable. Verify that the string: starts with the expected period name, contains "min", and does not crash.

### 2.1 inSession text format
- Construct a state with `dayState = .inSession`, `currentSlot` with `displayName = "Chemistry"` and `timeRemaining = 2520` (42 minutes).
- Assert: output == `"42 min left in Chemistry"`

### 2.2 inSession rounds up partial minutes
- `timeRemaining = 2521` (42 min 1 sec)
- Assert: output == `"43 min left in Chemistry"` (ceil)

### 2.3 afterSchool text
- State with `dayState = .afterSchool`
- Assert: output == `"School's out"`

### 2.4 noSchedule text
- State with `dayState = .noSchedule`
- Assert: output == `"No schedule today"`

### 2.5 holiday text
- State with `dayState = .holiday`
- Assert: output == `"No school today"`

### 2.6 pathwaysDay text
- State with `dayState = .pathwaysDay`
- Assert: output == `"Pathways Day — off campus"`

### 2.7 headerSecondaryText inSession includes next period name
- State with `dayState = .inSession`, `nextSlot` with `displayName = "Lunch"`, `startDate` = any future date
- Assert: output contains `"Next: Lunch"`

### 2.8 headerSecondaryText nil when no next slot
- State with `dayState = .inSession`, `nextSlot = nil`
- Assert: `headerSecondaryText` returns `nil`

---

## 3. ICalParserTests

File: `LHS LifeTests/ICalParserTests.swift`

Tests `ICalParser.parse()`. All inputs are raw iCal strings constructed inline.

### 3.1 Parses a minimal VEVENT
```
BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:test-uid-1\r\nSUMMARY:Regular Schedule\r\nDTSTART:20260505\r\nDTEND:20260505\r\nEND:VEVENT\r\nEND:VCALENDAR
```
- Assert: returns exactly 1 event
- Assert: `event.id == "test-uid-1"`
- Assert: `event.title == "Regular Schedule"`
- Assert: `event.isAllDay == true`

### 3.2 Parses a timed event (floating Pacific)
```
DTSTART:20260505T080000
DTEND:20260505T085000
```
- Assert: `event.isAllDay == false`
- Assert: start hour == 8, start minute == 0 in Pacific time

### 3.3 Parses a UTC datetime
```
DTSTART:20260505T150000Z
```
- Assert: `event.isAllDay == false`
- Assert: stored date equals May 5 2026 15:00 UTC

### 3.4 Line unfolding
Long SUMMARY split across two lines with CRLF + space:
```
SUMMARY:This is a very long summ\r\n ary that is folded
```
- Assert: `event.title == "This is a very long summary that is folded"`

### 3.5 TZID parameter stripped from key
```
DTSTART;TZID=America/Los_Angeles:20260505T080000
```
- Assert: parsed successfully (no crash, no nil result)
- Assert: `event.isAllDay == false`

### 3.6 Text unescaping
```
SUMMARY:Chemistry\, AP\nSecond line\;done
```
- Assert: `event.title == "Chemistry, AP\nSecond line;done"`

### 3.7 Missing UID returns no event
- VEVENT block with no UID line
- Assert: returns 0 events

### 3.8 Missing SUMMARY returns no event
- VEVENT block with UID but no SUMMARY
- Assert: returns 0 events

### 3.9 Missing DTSTART returns no event
- VEVENT block with UID and SUMMARY but no DTSTART
- Assert: returns 0 events

### 3.10 Multiple VEVENTs parsed correctly
- Feed with 3 distinct VEVENTs
- Assert: returns exactly 3 events with distinct IDs

### 3.11 LOCATION parsed correctly
- `LOCATION:Red Lion Hotel`
- Assert: `event.location == "Red Lion Hotel"`

### 3.12 DESCRIPTION with iCal escape sequences
- `DESCRIPTION:Math HW\\nChapter 4\\, problems 1-10`
- Assert: `event.description == "Math HW\nChapter 4, problems 1-10"`

---

## 4. BellScheduleParserTests

File: `LHS LifeTests/BellScheduleParserTests.swift`

Tests `BellScheduleParser.parse(from:)`. All inputs are `SchoolEvent` values with crafted `description` strings matching the exact format produced by CalendarWiz.

Reference description (exact format from the live feed):
```
Regular Schedule | Monday, Tuesday, Friday
Regular Schedule (1-7)
First Bell @ 7:55AM | 50 minute classes
Period
Begin
End
Total
0
6:45
7:45
60
1
8:00
8:50
50
Break
9:45
9:55
10
3
10:00
10:50
50
Lunch
11:45
12:15
30
```

### 4.1 Parses all periods from reference description
- Assert: returns a non-nil `BellSchedule`
- Assert: `periods.count == 6` (Period 0, Period 1, Break, Period 3, Lunch — total from reference)
- Assert: `periods[0].name == "Period 0"`
- Assert: `periods[1].name == "Period 1"`
- Assert: `periods[2].name == "Break"`
- Assert: `periods[3].name == "Period 3"`
- Assert: `periods[4].name == "Lunch"`

### 4.2 Period start times parsed correctly
- Period 1 start: hour == 8, minute == 0
- Break start: hour == 9, minute == 45
- Lunch start: hour == 11, minute == 45

### 4.3 Period end times parsed correctly
- Period 1 end: hour == 8, minute == 50
- Lunch end: hour == 12, minute == 15

### 4.4 Duration computed correctly from DateComponents
- Period 1: `durationMinutes == 50`
- Lunch: `durationMinutes == 30`

### 4.5 Schedule type inferred as regular
- Description contains "Regular Schedule"
- Assert: `scheduleType == .regular`

### 4.6 Schedule type inferred as lateStart
- Description contains "Late Start"
- Assert: `scheduleType == .lateStart`

### 4.7 Schedule type inferred as block
- Description contains "Block Schedule"
- Assert: `scheduleType == .block`

### 4.8 Schedule type inferred as earlyRelease
- Description contains "Early Release"
- Assert: `scheduleType == .earlyRelease`

### 4.9 PM times without meridiem suffix
- Time "1:15" (hour 1, treated as PM since < 6) → hour == 13, minute == 15
- Assert: Period 6 start time hour == 13

### 4.10 Times with AM suffix
- "7:55AM" → hour == 7, minute == 55
- Assert: parsed correctly with no 12-hour offset applied

### 4.11 Returns nil when no "Period" header found
- Description with no "Period" line
- Assert: `parse(from:)` returns nil

### 4.12 Returns nil when description is nil
- `SchoolEvent.description == nil`
- Assert: `parse(from:)` returns nil

### 4.13 Returns nil when description is empty
- `SchoolEvent.description == ""`
- Assert: `parse(from:)` returns nil

### 4.14 Period names normalized
- "0" → "Period 0"
- "1" → "Period 1"
- "break" → "Break"
- "lunch" → "Lunch"
- "ADVISORY" → "Advisory"

---

## 5. BellScheduleDetectorTests

File: `LHS LifeTests/BellScheduleDetectorTests.swift`

Tests `BellScheduleDetector.category(title:description:)` and `looksLikeBellSchedule(title:description:)`.

### 5.1 Bell schedule detection — title contains "schedule"
- title: "Regular Schedule", description: nil
- Assert: `category == .bellSchedule`

### 5.2 Bell schedule detection — title contains "bell schedule"
- Assert: `category == .bellSchedule`

### 5.3 Bell schedule detection — title contains "late start"
- Assert: `category == .bellSchedule`

### 5.4 Athletic — "golf"
- title: "Golf at Yakima CC"
- Assert: `category == .athletic`

### 5.5 Athletic — "vs."
- title: "Softball vs. Eisenhower"
- Assert: `category == .athletic`

### 5.6 Athletic — "basketball"
- title: "Boys Basketball Game"
- Assert: `category == .athletic`

### 5.7 Athletic — " vs " (with spaces)
- title: "Soccer LaSalle vs Davis"
- Assert: `category == .athletic`

### 5.8 Liturgy — "mass"
- title: "All School Mass"
- Assert: `category == .liturgy`

### 5.9 Holiday — "no school"
- title: "No School — Staff Development"
- Assert: `category == .holiday`

### 5.10 Other — no matching keyword
- title: "Prom - A Night Under the Stars"
- Assert: `category == .other`

### 5.11 Bell schedule takes priority over athletic keywords
- title: "Track Schedule"
- Assert: `category == .bellSchedule` (bell schedule check runs first)

### 5.12 Case insensitivity
- title: "GOLF TOURNAMENT"
- Assert: `category == .athletic`

---

## 6. PathwaysServiceTests

File: `LHS LifeTests/PathwaysServiceTests.swift`

Tests `PathwaysService.isEligible(graduationYear:on:)`, `isPathwaysEvent(_:)`, and `isPathwaysDay(on:events:graduationYear:referenceDate:)`.

Reference: school year starting August 2025 → seniors graduate 2026, juniors graduate 2027.

### 6.1 schoolYear — August is start of new school year
- `schoolYear(for: makeDate(2025, 8, 1, 12, 0))` → 2025
- `schoolYear(for: makeDate(2025, 7, 31, 12, 0))` → 2024

### 6.2 Senior is eligible
- `isEligible(graduationYear: 2026, on: makeDate(2025, 9, 1, 12, 0))` → true

### 6.3 Junior is eligible
- `isEligible(graduationYear: 2027, on: makeDate(2025, 9, 1, 12, 0))` → true

### 6.4 Sophomore is not eligible
- `isEligible(graduationYear: 2028, on: makeDate(2025, 9, 1, 12, 0))` → false

### 6.5 Freshman is not eligible
- `isEligible(graduationYear: 2029, on: makeDate(2025, 9, 1, 12, 0))` → false

### 6.6 isPathwaysEvent — title contains "Pathways"
- event with title "Pathways Day — Junior/Senior"
- Assert: `isPathwaysEvent(event) == true`

### 6.7 isPathwaysEvent — title contains "pathway" (singular)
- Assert: `isPathwaysEvent(event) == true`

### 6.8 isPathwaysEvent — unrelated title
- title: "AP Biology Review"
- Assert: `isPathwaysEvent(event) == false`

### 6.9 isPathwaysDay — eligible student + pathways event on that day
- Create event with title "Pathways Day", startDate on 2026-04-10
- Call `isPathwaysDay(on: "2026-04-10", events: [event], graduationYear: 2026, referenceDate: makeDate(2025, 9, 1, ...))`
- Assert: true

### 6.10 isPathwaysDay — ineligible student
- Same setup but `graduationYear: 2028`
- Assert: false

### 6.11 isPathwaysDay — eligible student but no pathways event on that day
- No events
- Assert: false

---

## 7. PeriodConfigTests

File: `LHS LifeTests/PeriodConfigTests.swift`

Tests `PeriodConfig.displayName` and `PeriodConfig.defaults`.

### 7.1 displayName uses customName when set
- `PeriodConfig(id: 3, customName: "Chemistry", colorIndex: 0, isEnabled: true).displayName == "Chemistry"`

### 7.2 displayName falls back to "Period N" when customName is empty
- `PeriodConfig(id: 3, customName: "", colorIndex: 0, isEnabled: true).displayName == "Period 3"`

### 7.3 displayName falls back to "Period N" when customName is whitespace
- `PeriodConfig(id: 3, customName: "   ", colorIndex: 0, isEnabled: true).displayName == "Period 3"`

### 7.4 Period 0 falls back to "Period 0"
- `PeriodConfig(id: 0, customName: "", colorIndex: 0, isEnabled: true).displayName == "Period 0"`

### 7.5 defaults has 9 entries (0–8)
- `PeriodConfig.defaults.count == 9`

### 7.6 defaults — period 0 is disabled
- `PeriodConfig.defaults[0].isEnabled == false`

### 7.7 defaults — period 8 is disabled
- `PeriodConfig.defaults[8].isEnabled == false`

### 7.8 defaults — periods 1–7 are enabled
- For i in 1...7: `PeriodConfig.defaults[i].isEnabled == true`

### 7.9 defaults — color indices match rainbow order
- `defaults[0].colorIndex == 0` (Slate)
- `defaults[1].colorIndex == 1` (Coral)
- `defaults[2].colorIndex == 2` (Peach)
- `defaults[3].colorIndex == 3` (Gold)
- `defaults[4].colorIndex == 4` (Mint)
- `defaults[5].colorIndex == 5` (Sky)
- `defaults[6].colorIndex == 6` (LaSalle Blue)
- `defaults[7].colorIndex == 7` (Lavender)
- `defaults[8].colorIndex == 0` (Slate)

---

## 8. ColorPaletteTests

File: `LHS LifeTests/ColorPaletteTests.swift`

### 8.1 Palette has exactly 10 colors
- `ColorPalette.colors.count == 10`

### 8.2 IDs are sequential 0–9
- `ColorPalette.colors.map(\.id) == [0,1,2,3,4,5,6,7,8,9]`

### 8.3 All hex strings are valid format
- Each `hex` starts with `#` and has length 7
- Each character after `#` is a valid hex digit

### 8.4 color(at:) clamps below zero
- `ColorPalette.color(at: -1).id == 0`

### 8.5 color(at:) clamps above 9
- `ColorPalette.color(at: 10).id == 9`
- `ColorPalette.color(at: 999).id == 9`

### 8.6 color(at:) returns correct entry
- `ColorPalette.color(at: 6).name == "LaSalle Blue"`
- `ColorPalette.color(at: 6).hex == "#3A6FD8"`

---

## 9. DateHelperTests (HomeworkPopup date logic)

File: `LHS LifeTests/DateHelperTests.swift`

The `nextMonday()` and `nextDay()` functions in `HomeworkPopup` are private. Extract them into a testable location — either move them to a `DateHelpers.swift` utility file, or expose them via `internal` access for testing. This refactor should happen before writing these tests.

### 9.1 nextDay returns tomorrow at midnight Pacific
- Call on a known date, assert result is exactly 24 hours later at midnight

### 9.2 nextMonday from Sunday returns Monday
- Reference day: Sunday 2026-05-03
- Assert: result is 2026-05-04 (Monday)

### 9.3 nextMonday from Monday returns next Monday (7 days)
- Reference day: Monday 2026-05-04
- Assert: result is 2026-05-11 (not same day)

### 9.4 nextMonday from Tuesday returns next Monday
- Reference day: Tuesday 2026-05-05
- Assert: result is 2026-05-11

### 9.5 nextMonday from Friday returns next Monday
- Reference day: Friday 2026-05-08
- Assert: result is 2026-05-11

### 9.6 nextMonday from Saturday returns next Monday
- Reference day: Saturday 2026-05-09
- Assert: result is 2026-05-11

### 9.7 nextMonday result is always a Monday
- For all 7 weekdays, assert that the result's weekday component == 2 (Monday in Gregorian)

---

## 10. SchoolEventTests

File: `LHS LifeTests/SchoolEventTests.swift`

### 10.1 dayKey format is yyyy-MM-dd
- Event with startDate = 2026-05-05 08:00 Pacific
- Assert: `event.dayKey == "2026-05-05"`

### 10.2 hasBellSchedule true for bellSchedule category
- Event with `category = .bellSchedule`
- Assert: `hasBellSchedule == true`

### 10.3 hasBellSchedule true when title contains "schedule"
- Event with `category = .other`, title = "Regular Schedule"
- Assert: `hasBellSchedule == true`

### 10.4 hasBellSchedule false for unrelated event
- title = "Prom", category = .other, description = nil
- Assert: `hasBellSchedule == false`

---

## 11. StaticAnalysisTests

File: `LHS LifeTests/StaticAnalysisTests.swift`

These tests use `FileManager` and string scanning to enforce architectural rules. They scan all `.swift` files in the app source directory.

**Setup:** Locate the source directory relative to the test bundle using `Bundle(for: type(of: self))`. Walk all `.swift` files in `LHS Life/` (excluding the test target and widget target).

### 11.1 No `@Published` in app source
- Scan all app `.swift` files for the string `@Published`
- Assert: zero occurrences
- Rationale: The app uses `@Observable`. `@Published` belongs to `ObservableObject` and must not appear.

### 11.2 No `@EnvironmentObject` in app source
- Scan for `@EnvironmentObject`
- Assert: zero occurrences
- Rationale: The app uses `@Environment(Type.self)`. `@EnvironmentObject` is the old pattern.

### 11.3 No `ObservableObject` conformance in app source
- Scan for `: ObservableObject`
- Assert: zero occurrences in non-service files
- Exception: `RemindersService` uses `@StateObject` and legitimately conforms. Exclude it.
- Rationale: All observable types use `@Observable`.

### 11.4 No `didSet` disk writes in UserSettings
- Scan `UserSettings.swift` for the pattern `didSet` containing `store.set` or `defaults.set`
- Assert: zero occurrences
- Rationale: Settings writes happen only in `save()`, never during property observation.

### 11.5 No magic numbers in view files
- Scan all files in `UI/` for numeric literals that are not: 0, 1, 0.0, 1.0, 0.5, 2, or referencing `LS.` spacing constants
- Flag any bare integer or float literals (e.g., `padding(16)`, `frame(height: 88)`) that do not use `LS.*` constants
- Assert: zero such occurrences
- Rationale: All visual constants must be in `DesignSystem.swift`.

### 11.6 Shared files are not importing UIKit or SwiftUI
- For each file marked `// Add this file to: LHS Life target + LHS Widgets target` in its header comment:
  - Assert: file does not contain `import UIKit`
  - Assert: file does not contain `import SwiftUI`
- Rationale: Widget extension does not link UIKit/SwiftUI in the same way; shared files must be framework-agnostic.

### 11.7 Telemetry print statements removed
- Scan all app `.swift` files for `// TELEMETRY` comments
- Assert: zero occurrences
- Rationale: Debug print statements in the header fire every second and must be removed before release.

---

## Running the Full Suite

```bash
xcodebuild test \
  -scheme "LHS Life" \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" \
  -only-testing "LHS LifeTests"
```

All 11 test classes must pass with zero failures and zero errors before any pull request or feature addition is merged.
