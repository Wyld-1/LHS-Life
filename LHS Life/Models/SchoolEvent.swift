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

    /// True if this event carries bell schedule information. CATEGORIES:Schedules
    /// (LaSalle's real CalendarWiz taxonomy) is the primary signal; the title
    /// keyword check is a fallback for the rare event missing a CATEGORIES tag.
    var hasBellSchedule: Bool {
        category == .schedules || BellScheduleDetector.looksLikeBellSchedule(title: title, description: description)
    }

    /// Professional Dress isn't its own CalendarWiz category — LaSalle tags
    /// "Professional Dress Day" itself as Student Activities, same as everything
    /// else in that bucket. This stays a title-based flag layered on top of the
    /// real category, not a category itself, so the schedule "floor rule" and
    /// the Siri intent both still have something reliable to key off of.
    var isProfessionalDress: Bool {
        BellScheduleDetector.isProfessionalDress(title: title)
    }

    /// Holiday also isn't its own CalendarWiz category in LaSalle's real
    /// taxonomy (no "Holiday" appeared anywhere in the 14 real categories) —
    /// title-detected the same way professional dress is, until we know how
    /// LaSalle actually tags these, if at all.
    var isHoliday: Bool {
        BellScheduleDetector.isHoliday(title: title)
    }

    /// Calendar-day identifier (yyyy-MM-dd) for grouping.
    var dayKey: String {
        DateFormatter.isoDay.string(from: startDate)
    }
}

// MARK: - EventCategory

/// LaSalle's real CalendarWiz category taxonomy — rawValues match the
/// CATEGORIES: property in the iCal feed exactly, so parsing is a direct
/// EventCategory(rawValue:) lookup. `.other` only exists as a fallback for
/// the rare event with no CATEGORIES tag at all (parsed via a title-keyword
/// heuristic in BellScheduleDetector, not a real LaSalle category).
enum EventCategory: String, Codable, CaseIterable {
    case academics              = "Academics"
    case admissions             = "Admissions"
    case advancementDevelopment = "Advancement/Development"
    case alumni                 = "Alumni"
    case athletics               = "Athletics"
    case campusMinistry         = "Campus Ministry"
    case counselingGuidance     = "Counseling/Guidance"
    case facilities              = "Facilities"
    case facultyStaff           = "Faculty/Staff"
    case parentAssociation      = "Parent Association"
    case schedules                = "Schedules"
    case service                 = "Service"
    case studentActivities       = "Student Activities"
    case visualPerformingArts    = "Visual and Performing Arts"
    case other                   = "Other"
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
