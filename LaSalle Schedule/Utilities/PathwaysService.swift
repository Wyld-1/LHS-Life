//
//  PathwaysService.swift
//  LaSalle Schedule
//
//  Determines whether a given date is a Pathways Day for a student,
//  based on their graduation year and event titles in the feed.
//
//  Pathways Days happen monthly and apply to juniors (gradYear - 1)
//  and seniors (gradYear). Events in the feed are consistently titled
//  with "Pathways" so we match on that keyword.
//
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation

enum PathwaysService {

    // MARK: - Eligibility

    /// Returns true if the student's graduation year makes them eligible
    /// for Pathways Days during the current school year.
    static func isEligible(graduationYear: Int, on date: Date = Date()) -> Bool {
        let currentYear = schoolYear(for: date)
        // Seniors graduate currentYear+1, juniors graduate currentYear+2
        // (school year starting in Aug YYYY ends in May YYYY+1)
        let seniorGradYear = currentYear + 1
        let juniorGradYear = currentYear + 2
        return graduationYear == seniorGradYear || graduationYear == juniorGradYear
    }

    // MARK: - Event Detection

    private static let pathwaysKeywords = ["pathways", "pathway"]

    /// Returns true if the event title/description indicates a Pathways Day.
    static func isPathwaysEvent(_ event: SchoolEvent) -> Bool {
        let combined = (event.title + " " + (event.description ?? "")).lowercased()
        return pathwaysKeywords.contains { combined.contains($0) }
    }

    /// Returns the Pathways Day event for a given dayKey, if one exists.
    static func pathwaysEvent(on dayKey: String, events: [SchoolEvent]) -> SchoolEvent? {
        events.first { $0.dayKey == dayKey && isPathwaysEvent($0) }
    }

    /// True if this student has Pathways off on the given day.
    static func isPathwaysDay(
        on dayKey: String,
        events: [SchoolEvent],
        graduationYear: Int,
        referenceDate: Date = Date()
    ) -> Bool {
        guard isEligible(graduationYear: graduationYear, on: referenceDate) else { return false }
        return pathwaysEvent(on: dayKey, events: events) != nil
    }

    // MARK: - School Year Helper

    /// Returns the starting calendar year of the current school year.
    /// e.g. Aug 2025 – May 2026 → returns 2025
    static func schoolYear(for date: Date = Date()) -> Int {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let year  = comps.year ?? 2025
        let month = comps.month ?? 1
        return month >= 8 ? year : year - 1
    }
}
