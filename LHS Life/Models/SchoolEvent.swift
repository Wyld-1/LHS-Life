//
//  SchoolEvent.swift
//  LaSalle Schedule
//
//  Represents a single event parsed from the CalendarWiz iCal feed.
//

import Foundation

/// A school event from the LaSalle CalendarWiz calendar.
struct SchoolEvent: Identifiable, Hashable, Codable {
    let id: String           // iCal UID
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let description: String?     // Raw iCal DESCRIPTION
    let htmlDescription: String?  // X-ALT-DESC — HTML, present on finals and some other events
    let url: URL?            // OPTIONAL: CalendarWiz popup URL for the event
    let category: EventCategory

    // MARK: - Derived

    /// True if this event carries bell schedule information.
    var hasBellSchedule: Bool {
        category == .bellSchedule || BellScheduleDetector.looksLikeBellSchedule(title: title, description: description)
    }

    /// Calendar-day identifier (yyyy-MM-dd) for grouping.
    var dayKey: String {
        DateFormatter.isoDay.string(from: startDate)
    }
}

// MARK: - EventCategory

/// Broad category buckets. CalendarWiz doesn't expose category IDs in the public iCal feed,
/// so we derive this from title/description heuristics at parse time.
enum EventCategory: String, Codable, CaseIterable {
    case bellSchedule    = "Bell Schedule"
    case athletic        = "Athletic"
    case academic        = "Academic"
    case liturgy         = "Liturgy"
    case holiday         = "Holiday"
    case professionalDress = "Professional Dress"
    case other           = "Other"
}

// MARK: - DateFormatter convenience

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return f
    }()
}
