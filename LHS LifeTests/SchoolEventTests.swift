//
//  SchoolEventTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class SchoolEventTests: XCTestCase {

    // MARK: 10.1 dayKey format is yyyy-MM-dd

    func test_dayKey_format() {
        let date  = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0)
        let event = makeEvent(title: "Test", startDate: date)
        XCTAssertEqual(event.dayKey, "2026-05-05")
    }

    // MARK: 10.2 hasBellSchedule true for bellSchedule category

    func test_hasBellSchedule_bellScheduleCategory() {
        let date  = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0)
        let event = makeEvent(title: "Anything", startDate: date, category: .bellSchedule)
        XCTAssertTrue(event.hasBellSchedule)
    }

    // MARK: 10.3 hasBellSchedule true when title contains "schedule"

    func test_hasBellSchedule_titleContainsSchedule() {
        let date  = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0)
        let event = makeEvent(title: "Regular Schedule", startDate: date, category: .other)
        XCTAssertTrue(event.hasBellSchedule)
    }

    // MARK: 10.4 hasBellSchedule false for unrelated event

    func test_hasBellSchedule_false() {
        let date  = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0)
        let event = makeEvent(title: "Prom", startDate: date, category: .other)
        XCTAssertFalse(event.hasBellSchedule)
    }
}
