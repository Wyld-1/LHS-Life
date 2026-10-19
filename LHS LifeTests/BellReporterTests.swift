//
//  BellReporterTests.swift
//  LHS LifeTests
//
//  The minutes sent to the worker decide when it broadcasts. A missing
//  minute is a bell where this card doesn't move.
//

import XCTest
@testable import LHS_Life

@MainActor
final class BellReporterTests: XCTestCase {

    private func slot(_ name: String, _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int,
                      day: Int = 20) -> ScheduleActivityAttributes.ScheduledPeriod {
        .init(periodNumber: nil, displayName: name, colorHex: "#94A3B8",
              startDate: makeDate(year: 2026, month: 10, day: day, hour: sh, minute: sm),
              endDate: makeDate(year: 2026, month: 10, day: day, hour: eh, minute: em),
              endTimeString: "")
    }

    func test_includesStartsAndEnds_dedupedAndSorted() {
        // Passing periods share both edges with the classes around them.
        let periods = [
            slot("Period 1", 8, 0, 8, 50),
            slot("Passing", 8, 50, 8, 55),
            slot("Period 2", 8, 55, 9, 45),
            slot("Lunch", 11, 45, 12, 15),   // gap before: 9:45 end must be there
        ]
        XCTAssertEqual(BellReporter.bellMinutes(for: periods),
                       [480, 530, 535, 585, 705, 735])
    }

    func test_lastEndIsIncluded() {
        let minutes = BellReporter.bellMinutes(for: [slot("Period 7", 14, 10, 15, 0)])
        XCTAssertEqual(minutes.last, 900)
    }

    func test_emptySchedule_isEmpty() {
        XCTAssertEqual(BellReporter.bellMinutes(for: []), [])
    }

    func test_minutesArePacific_notThePhonesZone() {
        // 8:00 AM Pacific is 11:00 AM Eastern. The worker's clock is Pacific,
        // so the default calendar must report 480 whatever zone the phone is in.
        let minutes = BellReporter.bellMinutes(for: [slot("Period 1", 8, 0, 8, 50)])
        XCTAssertEqual(minutes, [480, 530])

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(BellReporter.bellMinutes(for: [slot("Period 1", 8, 0, 8, 50)], calendar: eastern),
                       [660, 710])
    }
}
