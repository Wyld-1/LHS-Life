//
//  BellScheduleDetectorTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class BellScheduleDetectorTests: XCTestCase {

    // MARK: 5.1 Bell schedule — title contains "schedule"

    func test_bellSchedule_titleContainsSchedule() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Regular Schedule", description: nil), .bellSchedule)
    }

    // MARK: 5.2 Bell schedule — title contains "bell schedule"

    func test_bellSchedule_titleContainsBellSchedule() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Bell Schedule Day", description: nil), .bellSchedule)
    }

    // MARK: 5.3 Bell schedule — title contains "late start"

    func test_bellSchedule_titleContainsLateStart() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Late Start Wednesday", description: nil), .bellSchedule)
    }

    // MARK: 5.4 Athletic — "golf"

    func test_athletic_golf() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Golf at Yakima CC", description: nil), .athletic)
    }

    // MARK: 5.5 Athletic — "vs."

    func test_athletic_vs_period() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Softball vs. Eisenhower", description: nil), .athletic)
    }

    // MARK: 5.6 Athletic — "basketball"

    func test_athletic_basketball() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Boys Basketball Game", description: nil), .athletic)
    }

    // MARK: 5.7 Athletic — " vs " (spaces)

    func test_athletic_vs_spaces() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Soccer LaSalle vs Davis", description: nil), .athletic)
    }

    // MARK: 5.8 Liturgy — "mass"

    func test_liturgy_mass() {
        XCTAssertEqual(BellScheduleDetector.category(title: "All School Mass", description: nil), .liturgy)
    }

    // MARK: 5.9 Holiday — "no school"

    func test_holiday_noSchool() {
        XCTAssertEqual(BellScheduleDetector.category(title: "No School — Staff Development", description: nil), .holiday)
    }

    // MARK: 5.10 Other — no matching keyword

    func test_other_noKeyword() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Prom - A Night Under the Stars", description: nil), .other)
    }

    // MARK: 5.11 Bell schedule takes priority over athletic keywords

    func test_bellSchedulePriority_overAthleticKeywords() {
        // "track" is athletic but "schedule" triggers bell check first
        XCTAssertEqual(BellScheduleDetector.category(title: "Track Schedule", description: nil), .bellSchedule)
    }

    // MARK: 5.12 Case insensitivity

    func test_caseInsensitivity_athletic() {
        XCTAssertEqual(BellScheduleDetector.category(title: "GOLF TOURNAMENT", description: nil), .athletic)
    }
}
