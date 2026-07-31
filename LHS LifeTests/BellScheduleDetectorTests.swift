//
//  BellScheduleDetectorTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class BellScheduleDetectorTests: XCTestCase {

    // MARK: 5.1 Bell schedule — title contains "schedule"

    func test_bellSchedule_titleContainsSchedule() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Regular Schedule", description: nil), .schedules)
    }

    // MARK: 5.2 Bell schedule — title contains "bell schedule"

    func test_bellSchedule_titleContainsBellSchedule() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Bell Schedule Day", description: nil), .schedules)
    }

    // MARK: 5.3 Bell schedule — title contains "late start"

    func test_bellSchedule_titleContainsLateStart() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Late Start Wednesday", description: nil), .schedules)
    }

    // MARK: 5.4 Athletics — "golf"

    func test_athletics_golf() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Golf at Yakima CC", description: nil), .athletics)
    }

    // MARK: 5.5 Athletics — "vs."

    func test_athletics_vs_period() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Softball vs. Eisenhower", description: nil), .athletics)
    }

    // MARK: 5.6 Athletics — "basketball"

    func test_athletics_basketball() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Boys Basketball Game", description: nil), .athletics)
    }

    // MARK: 5.7 Athletics — " vs " (spaces)

    func test_athletics_vs_spaces() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Soccer LaSalle vs Davis", description: nil), .athletics)
    }

    // MARK: 5.8 Campus Ministry — "mass"
    // Was .liturgy pre-taxonomy-rewrite — LaSalle's real category is
    // "Campus Ministry", so the fallback heuristic now targets that instead.

    func test_campusMinistry_mass() {
        XCTAssertEqual(BellScheduleDetector.category(title: "All School Mass", description: nil), .campusMinistry)
    }

    // MARK: 5.9 Faculty/Staff — "staff"
    // Was asserted as .holiday pre-taxonomy-rewrite, testing the old
    // category()'s built-in holiday branch. Holiday isn't a real CalendarWiz
    // category (doesn't appear anywhere in LaSalle's real 14-category list)
    // and isn't part of category() anymore — it's now a fully separate
    // title-detected flag (isHoliday), tested below. What THIS title
    // actually exercises now is the "staff" keyword in the fallback
    // heuristic, since "No School" itself isn't one of the bell/athletics/
    // faculty/campus-ministry/academics keywords category() checks for.

    func test_facultyStaff_staffKeyword() {
        XCTAssertEqual(BellScheduleDetector.category(title: "No School — Staff Development", description: nil), .facultyStaff)
    }

    // MARK: 5.9b Holiday is now a separate title-detected flag, not a category

    func test_isHoliday_noSchoolKeyword() {
        XCTAssertTrue(BellScheduleDetector.isHoliday(title: "No School — Staff Development"))
    }

    func test_isHoliday_falseForUnrelatedTitle() {
        XCTAssertFalse(BellScheduleDetector.isHoliday(title: "All School Mass"))
    }

    // MARK: 5.10 Other — no matching keyword

    func test_other_noKeyword() {
        XCTAssertEqual(BellScheduleDetector.category(title: "Prom - A Night Under the Stars", description: nil), .other)
    }

    // MARK: 5.11 Bell schedule takes priority over athletics keywords

    func test_bellSchedulePriority_overAthleticsKeywords() {
        // "track" is athletics but "schedule" triggers bell check first
        XCTAssertEqual(BellScheduleDetector.category(title: "Track Schedule", description: nil), .schedules)
    }

    // MARK: 5.12 Case insensitivity

    func test_caseInsensitivity_athletics() {
        XCTAssertEqual(BellScheduleDetector.category(title: "GOLF TOURNAMENT", description: nil), .athletics)
    }

    // MARK: 5.13 Professional Dress — now a separate title-detected flag,
    // not a category (LaSalle tags Pro Dress Day itself as Student Activities)

    func test_isProfessionalDress_true() {
        XCTAssertTrue(BellScheduleDetector.isProfessionalDress(title: "Professional Dress Day"))
    }

    func test_isProfessionalDress_falseForUnrelatedTitle() {
        XCTAssertFalse(BellScheduleDetector.isProfessionalDress(title: "All School Mass"))
    }
}
