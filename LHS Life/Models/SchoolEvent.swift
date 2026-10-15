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

    /// A day off: a Schedules-category event whose title says so ("No School
    /// - Thanksgiving Holiday", "Christmas Break", "Labor Day - School
    /// Holiday"). Every real day off in the 2026–27 feed is posted that way.
    ///
    /// The category matters. This once matched holiday WORDS in any title,
    /// so "Christmas Wreaths - 1st Collection" (a fundraiser) made Oct 15 a
    /// "holiday": the header said "No school today" over Period 6, and the
    /// Live Activity was ended every second and restarted every second.
    var isHoliday: Bool {
        category == .schedules && BellScheduleDetector.isHoliday(title: title)
    }

    /// Calendar-day identifier (yyyy-MM-dd) for grouping.
    var dayKey: String {
        DateFormatter.isoDay.string(from: startDate)
    }

    /// A La Salle athletics event played at home.
    ///
    /// CalendarWiz has no home/away field, but the titles are consistent:
    /// home games say where they are — "Volleyball with Highland at La Salle",
    /// "Football with Goldendale at Marquette 7 PM" — and away games name the
    /// other school's town ("Football at Granger 7 PM"). Camps and parent
    /// meetings held at La Salle are athletics events too, but not games.
    var isHomeGame: Bool {
        guard category == .athletics else { return false }
        let t = title.lowercased()
        let atHome = t.contains("at la salle") || t.contains("at marquette")
            || t.contains("hosting") || t.contains("hosted on campus")
        let notAGame = ["camp", "meeting", "clinic", "tryout"].contains { t.contains($0) }
        return atHome && !notAGame
    }

    /// The sport a game is for, used to find its dress-up theme. Nil if the
    /// title doesn't name one.
    var sport: String? {
        let t = title.lowercased()
        return ["football", "volleyball", "soccer", "basketball", "cross country"].first { t.contains($0) }
    }

    /// The start time written in the TITLE of an all-day event, on its day.
    ///
    /// CalendarWiz's athletics entries are posted as all-day events with the
    /// time only in the title — "Football with Goldendale at Marquette 7 PM",
    /// "Cross Country at Warden 3:45 pm" — so the event itself says nothing
    /// about when, and the app used to show "All day" for a 7 PM kickoff.
    /// Needs an AM/PM marker, so a number like "3000 Lightning Way" never
    /// counts; with several times ("Girls at 2:45 PM, Boys at 4:15 PM") the
    /// first one wins. Nil for timed events and multi-day ones.
    var timeFromTitle: Date? {
        guard isAllDay else { return nil }
        let cal = Calendar.current
        let lastDay = cal.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        guard cal.isDate(startDate, inSameDayAs: lastDay) || endDate <= startDate else { return nil }

        let pattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s*m\b\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let hRange = Range(m.range(at: 1), in: title),
              var hour = Int(title[hRange]), (1...12).contains(hour)
        else { return nil }
        let minute = Range(m.range(at: 2), in: title).flatMap { Int(title[$0]) } ?? 0
        let isPM = Range(m.range(at: 3), in: title).map { title[$0].lowercased() == "p" } ?? false
        if isPM, hour < 12 { hour += 12 }
        if !isPM, hour == 12 { hour = 0 }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: startDate)
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
