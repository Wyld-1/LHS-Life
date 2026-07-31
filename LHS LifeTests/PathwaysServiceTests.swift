//
//  PathwaysServiceTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class PathwaysServiceTests: XCTestCase {

    // MARK: 6.1 schoolYear — August starts a new school year

    func test_schoolYear_augustIsStart() {
        XCTAssertEqual(PathwaysService.schoolYear(for: makeDate(year: 2025, month: 8, day: 1, hour: 12, minute: 0)), 2025)
        XCTAssertEqual(PathwaysService.schoolYear(for: makeDate(year: 2025, month: 7, day: 31, hour: 12, minute: 0)), 2024)
    }

    // MARK: 6.2 Senior is eligible

    func test_senior_isEligible() {
        // School year 2025 (Aug 2025 – May 2026): senior grad year = 2026
        let ref = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertTrue(PathwaysService.isEligible(graduationYear: 2026, on: ref))
    }

    // MARK: 6.3 Junior is eligible

    func test_junior_isEligible() {
        let ref = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertTrue(PathwaysService.isEligible(graduationYear: 2027, on: ref))
    }

    // MARK: 6.4 Sophomore is not eligible

    func test_sophomore_notEligible() {
        let ref = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertFalse(PathwaysService.isEligible(graduationYear: 2028, on: ref))
    }

    // MARK: 6.5 Freshman is not eligible

    func test_freshman_notEligible() {
        let ref = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertFalse(PathwaysService.isEligible(graduationYear: 2029, on: ref))
    }

    // MARK: 6.6 isPathwaysEvent — title contains "Pathways"

    func test_isPathwaysEvent_titleContainsPathways() {
        let event = makeEvent(title: "Pathways Day — Junior/Senior",
                              startDate: makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0))
        XCTAssertTrue(PathwaysService.isPathwaysEvent(event))
    }

    // MARK: 6.7 isPathwaysEvent — title contains "pathway" (singular)

    func test_isPathwaysEvent_singularPathway() {
        let event = makeEvent(title: "Pathway Internship Day",
                              startDate: makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0))
        XCTAssertTrue(PathwaysService.isPathwaysEvent(event))
    }

    // MARK: 6.8 isPathwaysEvent — unrelated title

    func test_isPathwaysEvent_unrelatedTitle() {
        let event = makeEvent(title: "AP Biology Review",
                              startDate: makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0))
        XCTAssertFalse(PathwaysService.isPathwaysEvent(event))
    }

    // MARK: 6.9 isPathwaysDay — eligible student + pathways event

    func test_isPathwaysDay_eligibleStudentWithEvent() {
        let eventDate = makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0)
        let event = makeEvent(title: "Pathways Day", startDate: eventDate, isAllDay: true)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dayKey = DateFormatter.isoDay.string(from: eventDate)
        let ref    = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertTrue(PathwaysService.isPathwaysDay(on: dayKey, events: [event],
                                                    graduationYear: 2026, referenceDate: ref))
    }

    // MARK: 6.10 isPathwaysDay — ineligible student

    func test_isPathwaysDay_ineligibleStudent() {
        let eventDate = makeDate(year: 2026, month: 4, day: 10, hour: 0, minute: 0)
        let event = makeEvent(title: "Pathways Day", startDate: eventDate, isAllDay: true)
        let dayKey = DateFormatter.isoDay.string(from: eventDate)
        let ref    = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertFalse(PathwaysService.isPathwaysDay(on: dayKey, events: [event],
                                                     graduationYear: 2028, referenceDate: ref))
    }

    // MARK: 6.11 isPathwaysDay — eligible but no event

    func test_isPathwaysDay_eligibleButNoEvent() {
        let dayKey = "2026-04-10"
        let ref    = makeDate(year: 2025, month: 9, day: 1, hour: 12, minute: 0)
        XCTAssertFalse(PathwaysService.isPathwaysDay(on: dayKey, events: [],
                                                     graduationYear: 2026, referenceDate: ref))
    }

    // MARK: 6.12 Grade level advances July 1, not August — a rising senior
    // (grad year 2027) in July counts as a senior, even though the school
    // year itself doesn't technically start until August.

    func test_gradeLevel_julyAdvancesToSenior() {
        let july = makeDate(year: 2026, month: 7, day: 15, hour: 12, minute: 0)
        XCTAssertEqual(PathwaysService.gradeLevel(graduationYear: 2027, on: july), 12)
    }

    // MARK: 6.13 Same graduation year in June is still the prior grade (junior)

    func test_gradeLevel_juneIsStillJunior() {
        let june = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
        XCTAssertEqual(PathwaysService.gradeLevel(graduationYear: 2027, on: june), 11)
    }
}
