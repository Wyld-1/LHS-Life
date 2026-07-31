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
    /// to the same event. Returns the array unmodified if there's no match
    /// or no resolvable grade (e.g. graduationYear not set yet).
    static func personalize(events: [SchoolEvent], graduationYear: Int) -> [SchoolEvent] {
        guard let index = events.firstIndex(where: {
            $0.title.trimmingCharacters(in: .whitespaces).lowercased() == "class orientation day"
        }) else { return events }
        guard let grade = PathwaysService.gradeLevel(graduationYear: graduationYear),
              let window = orientationWindow(forGrade: grade)
        else { return events }

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
