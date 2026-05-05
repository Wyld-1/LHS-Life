//
//  DateHelperTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class DateHelperTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    // MARK: 9.1 nextDay returns tomorrow at midnight

    func test_nextDay_returnsTomorrowAtMidnight() {
        let input    = makeDate(year: 2026, month: 5, day: 5, hour: 10, minute: 0)
        let result   = nextDay(from: input)
        let expected = makeDate(year: 2026, month: 5, day: 6, hour: 0, minute: 0)
        XCTAssertEqual(result, expected)
    }

    // MARK: 9.2 nextMonday from Sunday returns Monday

    func test_nextMonday_fromSunday_returnsMonday() {
        let sunday = makeDate(year: 2026, month: 5, day: 3, hour: 10, minute: 0)   // 2026-05-03 is a Sunday
        let result = nextMonday(from: sunday)
        let comps  = cal.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 4)   // 2026-05-04 is Monday
    }

    // MARK: 9.3 nextMonday from Monday returns NEXT Monday (7 days)

    func test_nextMonday_fromMonday_returnsNextWeekMonday() {
        let monday = makeDate(year: 2026, month: 5, day: 4, hour: 10, minute: 0)
        let result = nextMonday(from: monday)
        let comps  = cal.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(comps.day, 11)   // 2026-05-11
    }

    // MARK: 9.4 nextMonday from Tuesday returns next Monday

    func test_nextMonday_fromTuesday_returnsNextMonday() {
        let tuesday = makeDate(year: 2026, month: 5, day: 5, hour: 10, minute: 0)
        let result  = nextMonday(from: tuesday)
        let comps   = cal.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(comps.day, 11)
    }

    // MARK: 9.5 nextMonday from Friday

    func test_nextMonday_fromFriday_returnsNextMonday() {
        let friday = makeDate(year: 2026, month: 5, day: 8, hour: 10, minute: 0)
        let result = nextMonday(from: friday)
        let comps  = cal.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(comps.day, 11)
    }

    // MARK: 9.6 nextMonday from Saturday

    func test_nextMonday_fromSaturday_returnsNextMonday() {
        let saturday = makeDate(year: 2026, month: 5, day: 9, hour: 10, minute: 0)
        let result   = nextMonday(from: saturday)
        let comps    = cal.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(comps.day, 11)
    }

    // MARK: 9.7 nextMonday result is always a Monday (weekday == 2)

    func test_nextMonday_alwaysReturnsAMonday() {
        let weekdays = [
            makeDate(year: 2026, month: 5, day: 3, hour: 12, minute: 0),  // Sun
            makeDate(year: 2026, month: 5, day: 4, hour: 12, minute: 0),  // Mon
            makeDate(year: 2026, month: 5, day: 5, hour: 12, minute: 0),  // Tue
            makeDate(year: 2026, month: 5, day: 6, hour: 12, minute: 0),  // Wed
            makeDate(year: 2026, month: 5, day: 7, hour: 12, minute: 0),  // Thu
            makeDate(year: 2026, month: 5, day: 8, hour: 12, minute: 0),  // Fri
            makeDate(year: 2026, month: 5, day: 9, hour: 12, minute: 0),  // Sat
        ]
        for date in weekdays {
            let result  = nextMonday(from: date)
            let weekday = cal.component(.weekday, from: result)
            XCTAssertEqual(weekday, 2, "nextMonday from \(date) returned weekday \(weekday), expected 2 (Monday)")
        }
    }
}
