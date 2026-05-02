//
//  ScheduleEngine.swift
//  LaSalle Schedule
//
//  The heart of the live features. Given a BellSchedule, UserSettings,
//  and a current time, answers every "what period is it?" question
//  the app and widgets need.
//
//  Stateless — all methods are pure functions of their inputs.
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation

enum ScheduleEngine {

    // MARK: - Core Types

    /// The complete state of the schedule at a given moment.
    struct ScheduleState {
        let date: Date
        let currentSlot: ActiveSlot?   // nil if school hasn't started or has ended
        let nextSlot: ActiveSlot?      // nil if nothing follows
        let dayState: DayState
    }

    /// A period or break that is either currently active or up next.
    struct ActiveSlot {
        let period: Period
        let config: PeriodConfig?      // nil for breaks/lunch (no config slot)
        let startDate: Date
        let endDate: Date

        var timeRemaining: TimeInterval { endDate.timeIntervalSince(Date()) }
        var duration: TimeInterval      { endDate.timeIntervalSince(startDate) }
        var progress: Double {          // 0.0 → 1.0
            let elapsed = Date().timeIntervalSince(startDate)
            return max(0, min(1, elapsed / duration))
        }
        var displayName: String { config?.displayName ?? period.name }
    }

    enum DayState {
        case beforeSchool              // Current time is before first period
        case inSession                 // School is actively running
        case betweenPeriods            // Between two periods (passing time / break)
        case afterSchool               // Past last period
        case noSchedule                // No bell schedule for this day
        case pathwaysDay               // Student is off for Pathways
        case holiday                   // School holiday / no school
    }

    // MARK: - Primary Entry Point

    /// Computes the full schedule state for the given moment.
    static func state(
        for date: Date = Date(),
        schedule: BellSchedule?,
        settings: UserSettings,
        isPathwaysDay: Bool = false,
        isHoliday: Bool = false
    ) -> ScheduleState {

        if isHoliday     { return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .holiday) }
        if isPathwaysDay { return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .pathwaysDay) }

        guard let schedule = schedule else {
            return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .noSchedule)
        }

        let enabledPeriods = visiblePeriods(from: schedule, settings: settings)
        guard !enabledPeriods.isEmpty else {
            return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .noSchedule)
        }

        let slots = enabledPeriods.compactMap { period -> (period: Period, start: Date, end: Date)? in
            guard let s = period.startDate(on: schedule.date),
                  let e = period.endDate(on: schedule.date) else { return nil }
            return (period, s, e)
        }.sorted { $0.start < $1.start }

        guard let firstSlot = slots.first, let lastSlot = slots.last else {
            return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .noSchedule)
        }

        if date < firstSlot.start {
            let next = makeActiveSlot(from: firstSlot, settings: settings, schedule: schedule)
            return ScheduleState(date: date, currentSlot: nil, nextSlot: next, dayState: .beforeSchool)
        }

        if date > lastSlot.end {
            return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .afterSchool)
        }

        // Find current slot
        for (i, slot) in slots.enumerated() {
            if date >= slot.start && date <= slot.end {
                let current = makeActiveSlot(from: slot, settings: settings, schedule: schedule)
                let next = i + 1 < slots.count
                    ? makeActiveSlot(from: slots[i + 1], settings: settings, schedule: schedule)
                    : nil
                return ScheduleState(date: date, currentSlot: current, nextSlot: next, dayState: .inSession)
            }
        }

        // Between periods
        for i in 0..<(slots.count - 1) {
            let thisEnd  = slots[i].end
            let nextStart = slots[i + 1].start
            if date > thisEnd && date < nextStart {
                let next = makeActiveSlot(from: slots[i + 1], settings: settings, schedule: schedule)
                return ScheduleState(date: date, currentSlot: nil, nextSlot: next, dayState: .betweenPeriods)
            }
        }

        return ScheduleState(date: date, currentSlot: nil, nextSlot: nil, dayState: .inSession)
    }

    // MARK: - Header String Helpers

    /// "42 min left in Chemistry"  /  "English in 8 min"  etc.
    static func headerPrimaryText(for state: ScheduleState) -> String {
        switch state.dayState {
        case .inSession:
            guard let slot = state.currentSlot else { return "" }
            let mins = Int(ceil(slot.timeRemaining / 60))
            return "\(mins) min left in \(slot.displayName)"
        case .betweenPeriods:
            guard let next = state.nextSlot else { return "" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(Date()) / 60))
            return "\(next.displayName) in \(mins) min"
        case .beforeSchool:
            guard let next = state.nextSlot else { return "No school today" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(Date()) / 60))
            return mins > 60
                ? "School starts at \(timeString(next.startDate))"
                : "School starts in \(mins) min"
        case .afterSchool:  return "School's out"
        case .noSchedule:   return "No schedule today"
        case .pathwaysDay:  return "Pathways Day — off campus"
        case .holiday:      return "No school today"
        }
    }

    static func headerSecondaryText(for state: ScheduleState) -> String? {
        switch state.dayState {
        case .inSession:
            guard let next = state.nextSlot else { return nil }
            return "Next: \(next.displayName) at \(timeString(next.startDate))"
        case .betweenPeriods:
            guard let next = state.nextSlot else { return nil }
            return "Until \(timeString(next.endDate))"
        default:
            return nil
        }
    }

    // MARK: - Private Helpers

    private static func visiblePeriods(from schedule: BellSchedule, settings: UserSettings) -> [Period] {
        schedule.periods.filter { period in
            // Special rows (Break, Lunch) are always shown
            guard let periodNum = extractPeriodNumber(from: period.name) else { return true }
            return settings.config(for: periodNum)?.isEnabled ?? true
        }
    }

    private static func extractPeriodNumber(from name: String) -> Int? {
        // "Period 3" → 3,  "Break" → nil,  "Lunch" → nil
        let parts = name.split(separator: " ")
        if parts.count == 2, parts[0].lowercased() == "period", let n = Int(parts[1]) {
            return n
        }
        return nil
    }

    private static func makeActiveSlot(
        from slot: (period: Period, start: Date, end: Date),
        settings: UserSettings,
        schedule: BellSchedule
    ) -> ActiveSlot {
        let periodNum = extractPeriodNumber(from: slot.period.name)
        let config    = periodNum.flatMap { settings.config(for: $0) }
        return ActiveSlot(period: slot.period, config: config, startDate: slot.start, endDate: slot.end)
    }

    static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: date)
    }
}
