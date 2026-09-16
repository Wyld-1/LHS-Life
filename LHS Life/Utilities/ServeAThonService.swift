//
//  ServeAThonService.swift
//  LHS Life
//
//  Serve-a-thon replaces a student's whole school day: 8:00 AM to 3:00 PM,
//  no classes, for that student's grade only. Every other grade has a normal
//  day, and so does anyone without a grade — staff, parents, alumni.
//
//  WHY THE DAYS ARE INFERRED
//
//  The four grades serve on four consecutive school days, in order: frosh,
//  soph, junior, senior. The feed does NOT reliably carry all four. In
//  2026-27 it has three — "Frosh Serve-a-thon" (Tue), "Soph Serve-a-thon
//  (regular bell schedule)" (Wed), "Senior Serve-A-Thon" (Fri) — and no
//  junior event at all, which would otherwise leave juniors sitting in
//  classes that aren't happening. So one event anchors the whole series:
//  from any grade's date, step back to the frosh day and lay out all four.
//
//  Titles are also not to be trusted for timing. The soph event says
//  "(regular bell schedule)" and the senior one is stamped 3–10 PM, but per
//  ASB both grades are out serving 8:00–3:00 like everyone else. The times
//  here are fixed, not read from the event.
//
//  Weekends are skipped when stepping between days, so a series that starts
//  on a Thursday puts juniors and seniors on the following Monday and
//  Tuesday rather than on the weekend.
//

import Foundation

enum ServeAThonService {

    /// 8:00 AM – 3:00 PM, the same for every grade.
    static let startHour = 8
    static let endHour   = 15

    static let periodName = "Serve-a-thon"

    /// Grades in the order they serve, which is also the order of the days.
    private static let gradesInOrder = [9, 10, 11, 12]

    /// Matched against the event title. "Frosh" is what LaSalle's feed uses;
    /// the rest are spelled out in case a future year's titles differ.
    private static let gradeKeywords: [(grade: Int, words: [String])] = [
        (9,  ["frosh", "freshman", "freshmen", "9th"]),
        (10, ["soph", "sophomore", "10th"]),
        (11, ["junior", "juniors", "jr", "11th"]),
        (12, ["senior", "seniors", "sr", "12th"]),
    ]

    // MARK: - Detection

    /// True for any Serve-a-thon event, however the feed spells it
    /// ("Serve-a-thon", "Serve-A-Thon", "Serve a thon").
    static func isServeAThonEvent(_ event: SchoolEvent) -> Bool {
        let squashed = event.title.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return squashed.contains("serveathon")
    }

    /// The grade named in a title, or nil if it names none.
    static func grade(inTitle title: String) -> Int? {
        let lower = title.lowercased()
        // Longest keywords first so "senior" isn't shadowed by a stray "sr".
        for (grade, words) in gradeKeywords {
            for word in words.sorted(by: { $0.count > $1.count }) where lower.contains(word) {
                return grade
            }
        }
        return nil
    }

    // MARK: - The series

    /// Every Serve-a-thon day in the feed, as grade → dayKey, including the
    /// grades whose own event is missing.
    ///
    /// An explicit event always wins for its own grade; the rest are filled
    /// in around it. Two series in one year (a fall and a spring round, say)
    /// produce two sets of four, since each anchor is expanded separately.
    static func seriesDays(in events: [SchoolEvent], calendar: Calendar = .current) -> [Int: Set<String>] {
        let anchors: [(grade: Int, date: Date)] = events.compactMap { event in
            guard isServeAThonEvent(event), let grade = grade(inTitle: event.title) else { return nil }
            return (grade, calendar.startOfDay(for: event.startDate))
        }
        guard !anchors.isEmpty else { return [:] }

        var days: [Int: Set<String>] = [:]
        // Each anchor implies a whole series. Anchors from the same series
        // land on the same start date and so produce identical days.
        for anchor in anchors {
            guard let start = schoolDay(before: anchor.date,
                                        steps: gradesInOrder.firstIndex(of: anchor.grade) ?? 0,
                                        calendar: calendar) else { continue }
            for (offset, grade) in gradesInOrder.enumerated() {
                guard let date = schoolDay(after: start, steps: offset, calendar: calendar) else { continue }
                days[grade, default: []].insert(DateFormatter.isoDay.string(from: date))
            }
        }
        return days
    }

    /// Every day in every series, whatever the grade. Serve-a-thon weeks are
    /// the one time the feed reliably omits its "Regular Schedule" markers —
    /// 2026-27 has none on the soph or junior days — so these are the days
    /// that need a regular schedule backfilled for everyone not serving.
    static func allSeriesDayKeys(in events: [SchoolEvent], calendar: Calendar = .current) -> Set<String> {
        seriesDays(in: events, calendar: calendar).values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// The student's own Serve-a-thon days. Empty for anyone without a
    /// current grade: staff, parents, alumni, and "not a student" accounts.
    static func serveDayKeys(
        events: [SchoolEvent],
        graduationYear: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<String> {
        guard let grade = PathwaysService.gradeLevel(graduationYear: graduationYear, on: referenceDate) else {
            return []
        }
        return seriesDays(in: events, calendar: calendar)[grade] ?? []
    }

    // MARK: - The schedule itself

    /// A whole day of Serve-a-thon: one block, 8:00 to 3:00.
    static func schedule(on date: Date, dayKey: String) -> BellSchedule {
        let period = Period(
            id: "serve-a-thon",
            name: periodName,
            startTime: DateComponents(hour: startHour, minute: 0),
            endTime: DateComponents(hour: endHour, minute: 0)
        )
        return BellSchedule(
            id: "serve-a-thon-\(dayKey)",
            date: date,
            scheduleType: .serveAThon,
            periods: [period],
            sourceEventID: "serve-a-thon"
        )
    }

    // MARK: - Weekday stepping

    private static func schoolDay(after date: Date, steps: Int, calendar: Calendar) -> Date? {
        step(from: date, steps: steps, direction: 1, calendar: calendar)
    }

    private static func schoolDay(before date: Date, steps: Int, calendar: Calendar) -> Date? {
        step(from: date, steps: steps, direction: -1, calendar: calendar)
    }

    private static func step(from date: Date, steps: Int, direction: Int, calendar: Calendar) -> Date? {
        var current = date
        var remaining = steps
        var guardRail = 0
        while remaining > 0 {
            guard let next = calendar.date(byAdding: .day, value: direction, to: current) else { return nil }
            current = next
            guardRail += 1
            if guardRail > 30 { return nil }   // never loop on a broken calendar
            let weekday = calendar.component(.weekday, from: current)
            guard weekday != 1 && weekday != 7 else { continue }  // skip Sun/Sat
            remaining -= 1
        }
        return current
    }
}
