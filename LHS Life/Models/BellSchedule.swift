//
//  BellSchedule.swift
//  LaSalle Schedule
//
//  Represents a parsed bell schedule for a specific school day.
//

import Foundation

/// A complete bell schedule for one school day.
struct BellSchedule: Identifiable, Hashable, Codable {
    let id: String            // Derived from the source event UID
    let date: Date
    let scheduleType: ScheduleType
    let periods: [Period]
    let sourceEventID: String // Links back to the SchoolEvent this was extracted from

    /// Calendar-day key for lookup (yyyy-MM-dd).
    var dayKey: String {
        DateFormatter.isoDay.string(from: date)
    }
}

// MARK: - ScheduleType

/// The flavor of schedule for the day.
enum ScheduleType: String, Codable, CaseIterable {
    case regular       = "Regular"
    case block         = "Block"
    case lateStart     = "Late Start"
    case earlyRelease  = "Early Release"
    case assembly      = "Assembly"
    case finals        = "Finals"
    case custom        = "Custom"
    case unknown       = "Unknown"
}

// MARK: - Period

/// A single class period or passing time within a bell schedule.
struct Period: Identifiable, Hashable, Codable {
    let id: String          // e.g. "1", "2", "Lunch", "Advisory"
    let name: String        // Display name: "Period 1", "Lunch", "Advisory", etc.
    let startTime: DateComponents  // Hour + minute only; apply to the schedule date
    let endTime: DateComponents

    /// Convenience: start as a Date given a reference date (midnight of schedule day).
    func startDate(on date: Date, calendar: Calendar = .current) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = startTime.hour
        comps.minute = startTime.minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    func endDate(on date: Date, calendar: Calendar = .current) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = endTime.hour
        comps.minute = endTime.minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// Duration in minutes.
    var durationMinutes: Int? {
        guard let sh = startTime.hour, let sm = startTime.minute,
              let eh = endTime.hour,  let em = endTime.minute else { return nil }
        return (eh * 60 + em) - (sh * 60 + sm)
    }
}

// MARK: - BellScheduleSource

/// Describes how the bell schedule data arrived — affects parsing strategy.
enum BellScheduleSource: Codable {
    case parsedText(rawText: String)   // Description contained parseable plain text
    case imageURL(url: URL)            // Description contained an image — needs OCR/Vision
    case manual                        // Hand-entered fallback
}
