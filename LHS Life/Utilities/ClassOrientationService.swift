//
//  ClassOrientationService.swift
//  LHS Life
//
//  Detects "Class Orientation Day" in the feed and personalizes it in the
//  app's own data model — swaps the generic all-day placeholder for a
//  timed event with the student's grade-specific window, so it shows up
//  correctly positioned in the Events tab like any other timed event.
//  No EventKit, no system Calendar — stays entirely inside the app, per
//  Lion's call.
//
//  Detection is deliberately an EXACT title match — LaSalle's feed has
//  several differently-named orientation events on the same day
//  ("Freshman & New Parent Orientation", "New Faculty Orientation", "New
//  Faculty Academics Introduction and Training") and a loose keyword match
//  would risk grabbing the wrong one.
//

import Foundation

enum ClassOrientationService {

    // MARK: - Grade-specific orientation windows
    // Exactly the times Lion gave: Freshmen 9–12, Sophomores 10–1,
    // Juniors 11–2, Seniors 12–3.

    struct OrientationWindow {
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
    }

    static func orientationWindow(forGrade grade: Int) -> OrientationWindow? {
        switch grade {
        case 9:  return OrientationWindow(startHour: 9,  startMinute: 0, endHour: 12, endMinute: 0)
        case 10: return OrientationWindow(startHour: 10, startMinute: 0, endHour: 13, endMinute: 0)
        case 11: return OrientationWindow(startHour: 11, startMinute: 0, endHour: 14, endMinute: 0)
        case 12: return OrientationWindow(startHour: 12, startMinute: 0, endHour: 15, endMinute: 0)
        default: return nil
        }
    }

    /// The union of every grade's window — earliest start to latest end.
    ///
    /// Used when there's no resolvable grade (staff, parents, anyone with
    /// "Not a student" set). They still get a real timed block covering the
    /// whole event rather than an all-day placeholder, since the event does
    /// happen at a specific time — we just can't narrow it to one grade.
    ///
    /// Derived from the windows above rather than hardcoded so it stays
    /// correct if the school moves the times.
    static var fullWindow: OrientationWindow {
        let windows = (9...12).compactMap { orientationWindow(forGrade: $0) }
        let starts  = windows.map { $0.startHour * 60 + $0.startMinute }
        let ends    = windows.map { $0.endHour   * 60 + $0.endMinute }
        let start   = starts.min() ?? 9  * 60
        let end     = ends.max()   ?? 15 * 60
        return OrientationWindow(
            startHour: start / 60, startMinute: start % 60,
            endHour:   end   / 60, endMinute:   end   % 60
        )
    }

    /// "9 AM" — report time when no grade is known.
    static var fullWindowStartLabel: String {
        hourLabel(fullWindow.startHour, fullWindow.startMinute)
    }

    /// "9 AM–12 PM" style range when no grade is known.
    static var fullWindowRangeLabel: String {
        "\(hourLabel(fullWindow.startHour, fullWindow.startMinute))"
        + "\u{2013}"
        + "\(hourLabel(fullWindow.endHour, fullWindow.endMinute))"
    }

    private static func hourLabel(_ hour: Int, _ minute: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0
            ? "\(h12) \(suffix)"
            : "\(h12):\(String(format: "%02d", minute)) \(suffix)"
    }

    /// Simple pre-formatted label — avoids building throwaway Date objects
    /// just to format a fixed, known time range.
    static func timeRangeLabel(forGrade grade: Int) -> String? {
        switch grade {
        case 9:  return "9 AM\u{2013}12 PM"
        case 10: return "10 AM\u{2013}1 PM"
        case 11: return "11 AM\u{2013}2 PM"
        case 12: return "12 PM\u{2013}3 PM"
        default: return nil
        }
    }

    /// Start time only — used by the notification body, which states just
    /// the report time rather than the full window.
    static func startTimeLabel(forGrade grade: Int) -> String? {
        switch grade {
        case 9:  return "9 AM"
        case 10: return "10 AM"
        case 11: return "11 AM"
        case 12: return "12 PM"
        default: return nil
        }
    }

    static func gradeLabel(forGrade grade: Int) -> String {
        switch grade {
        case 9:  return "Freshmen"
        case 10: return "Sophomores"
        case 11: return "Juniors"
        case 12: return "Seniors"
        default: return "Students"
        }
    }

    // MARK: - Personalization

    /// Finds "Class Orientation Day" (exact title match) and replaces it
    /// with a timed copy reflecting the student's grade-specific window —
    /// same UID, so tap-to-detail and the notification both still resolve
    /// to the same event.
    ///
    /// With no resolvable grade (staff, parents, "Not a student") it falls
    /// back to `fullWindow` — earliest start to latest end — rather than
    /// leaving the event as an untimed all-day row. The event is real and
    /// timed for everyone; only the narrowing is grade-specific.
    static func personalize(events: [SchoolEvent], graduationYear: Int) -> [SchoolEvent] {
        guard let index = events.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespaces).lowercased() == "class orientation day"
        }) else { return events }

        let grade  = PathwaysService.gradeLevel(graduationYear: graduationYear)
        let window = grade.flatMap { orientationWindow(forGrade: $0) } ?? fullWindow

        let original = events[index]
        let cal = Calendar.current
        guard let start = cal.date(bySettingHour: window.startHour, minute: window.startMinute, second: 0, of: original.startDate),
              let end   = cal.date(bySettingHour: window.endHour,   minute: window.endMinute,   second: 0, of: original.startDate)
        else { return events }

        let personalized = SchoolEvent(
            id: original.id,
            title: original.title,
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: original.location,
            description: original.description,
            htmlDescription: original.htmlDescription,
            url: original.url,
            category: original.category
        )

        var updated = events
        updated[index] = personalized
        return updated
    }
}
