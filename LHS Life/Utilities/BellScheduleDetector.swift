//
//  BellScheduleDetector.swift
//  LaSalle Schedule
//
//  Heuristics for detecting whether an event is bell-schedule related
//  and for assigning EventCategory from title/description text.
//

import Foundation

enum BellScheduleDetector {

    // MARK: - Bell Schedule Detection

    private static let bellKeywords: [String] = [
        "bell schedule", "block schedule", "late start", "early release",
        "early dismissal", "schedule", "period", "modified day",
        "senior presentation",
    ]

    static func looksLikeBellSchedule(title: String, description: String?) -> Bool {
        let combined = (title + " " + (description ?? "")).lowercased()
        return bellKeywords.contains { combined.contains($0) }
    }

    /// Title-only check — used for category assignment to avoid miscategorizing
    /// events that merely embed a schedule table in their description.
    static func looksLikeBellScheduleTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        // Senior Presentation day has no machine-readable description but IS a
        // schedule event — detect by title before the keyword check.
        if t.contains("senior presentation") { return true }
        // Finals events contain "exam" which BellScheduleDetector.category would
        // otherwise catch first and return .academic, hiding them from the parser.
        if t.contains("final exam") || t.contains("finals") { return true }
        return bellKeywords.contains { t.contains($0) }
    }

    // MARK: - Category Inference (fallback only)
    //
    // LaSalle's real feed tags every event with CATEGORIES:, which
    // ICalParser reads directly via EventCategory(rawValue:) — this is now
    // just the safety net for the rare event with no CATEGORIES property at
    // all, so it doesn't need to be exhaustive the way it used to.

    static func category(title: String, description: String?) -> EventCategory {
        let t = title.lowercased()
        if looksLikeBellScheduleTitle(title) { return .schedules }
        if t.contains("game") || t.contains("match") || t.contains("tournament")
            || t.contains("athletic") || t.contains("sport")
            || t.contains("golf") || t.contains("tennis") || t.contains("swim")
            || t.contains("basketball") || t.contains("baseball") || t.contains("softball")
            || t.contains("soccer") || t.contains("football") || t.contains("volleyball")
            || t.contains("track") || t.contains("cross country") || t.contains("wrestling")
            || t.contains("lacrosse") || t.contains("vs.") || t.contains(" vs ") { return .athletics }
        if t.contains("faculty") || t.contains("staff") { return .facultyStaff }
        if t.contains("mass") || t.contains("liturgy") || t.contains("prayer")
            || t.contains("retreat") || t.contains("chapel") { return .campusMinistry }
        if t.contains("exam") || t.contains("test") || t.contains("finals")
            || t.contains("graduation") || t.contains("ap ") { return .academics }
        return .other
    }

    // MARK: - Professional Dress
    //
    // Not a real CalendarWiz category (LaSalle tags Pro Dress Day itself as
    // Student Activities) — title-detected the same way it always was. This
    // is now the single canonical list; NotificationService used to keep its
    // own separate copy, which has been folded in here (its list was the
    // more complete one, so that's the version that survived).
    private static let dressKeywords = [
        "professional dress", "formal dress", "mass attire",
        "dress uniform", "professional attire", "formal attire"
    ]

    static func isProfessionalDress(title: String) -> Bool {
        let t = title.lowercased()
        return dressKeywords.contains { t.contains($0) }
    }

    // MARK: - Holiday
    //
    // Not a real CalendarWiz category either — title-detected as a stopgap
    // until we confirm how (or if) LaSalle's feed actually tags these.
    private static let holidayKeywords = [
        "holiday", "no school", "christmas", "thanksgiving",
        "winter break", "spring break", "summer break"
    ]

    static func isHoliday(title: String) -> Bool {
        let t = title.lowercased()
        return holidayKeywords.contains { t.contains($0) }
    }
}
