//
//  ScheduleEngineTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class ScheduleEngineTests: XCTestCase {

    // MARK: 1.1 Holiday override

    func test_holidayOverride_setsHolidayState() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 10, minute: 0)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings(), isHoliday: true)
        XCTAssertEqual(result.dayState, .holiday)
        XCTAssertNil(result.currentSlot)
        XCTAssertNil(result.nextSlot)
    }

    // MARK: 1.2 Pathways Day override

    func test_pathwaysDayOverride_setsPathwaysState() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 10, minute: 0)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings(), isPathwaysDay: true)
        XCTAssertEqual(result.dayState, .pathwaysDay)
        XCTAssertNil(result.currentSlot)
        XCTAssertNil(result.nextSlot)
    }

    // MARK: 1.3 No schedule

    func test_noSchedule_setsNoScheduleState() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 10, minute: 0)
        let result = ScheduleEngine.state(for: date, schedule: nil,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .noSchedule)
        XCTAssertNil(result.currentSlot)
        XCTAssertNil(result.nextSlot)
    }

    // MARK: 1.4 Before school

    func test_beforeSchool_returnsCorrectState() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 7, minute: 30)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .beforeSchool)
        XCTAssertNil(result.currentSlot)
        XCTAssertEqual(result.nextSlot?.period.name, "Period 1")
    }

    // MARK: 1.5 Exactly at period start

    func test_exactlyAtPeriodStart_isInSession() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0, second: 0)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .inSession)
        XCTAssertEqual(result.currentSlot?.period.name, "Period 1")
    }

    // MARK: 1.6 Mid-period (next slot is Period 2, which immediately follows P1)

    func test_midPeriod_currentAndNextSlotCorrect() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 25)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .inSession)
        XCTAssertEqual(result.currentSlot?.period.name, "Period 1")
        XCTAssertEqual(result.nextSlot?.period.name, "Period 2")
    }

    // MARK: 1.7 Exactly at period end

    func test_exactlyAtPeriodEnd_isInSession() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 50, second: 0)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .inSession)
        XCTAssertEqual(result.currentSlot?.period.name, "Period 1")
    }

    // MARK: 1.8 Between periods

    func test_betweenPeriods_returnsCorrectState() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 51)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .betweenPeriods)
        XCTAssertNil(result.currentSlot)
        XCTAssertEqual(result.nextSlot?.period.name, "Period 2")
    }

    // MARK: 1.9 During Break

    func test_duringBreak_isInSession() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 48)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .inSession)
        XCTAssertEqual(result.currentSlot?.period.name, "Break")
    }

    // MARK: 1.10 During Lunch

    func test_duringLunch_isInSession() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 12, minute: 0)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .inSession)
        XCTAssertEqual(result.currentSlot?.period.name, "Lunch")
    }

    // MARK: 1.11 After last period

    func test_afterLastPeriod_isAfterSchool() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 15, minute: 1)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.dayState, .afterSchool)
        XCTAssertNil(result.currentSlot)
        XCTAssertNil(result.nextSlot)
    }

    // MARK: 1.12 Last period has no next slot

    func test_lastPeriod_nextSlotIsNil() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 14, minute: 30)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule,
                                          settings: makeDefaultSettings())
        XCTAssertEqual(result.currentSlot?.period.name, "Period 7")
        XCTAssertNil(result.nextSlot)
    }

    // MARK: 1.13 Disabled period is skipped

    func test_disabledPeriod_isSkipped() {
        var settings = makeDefaultSettings()
        if let idx = settings.periodConfigs.firstIndex(where: { $0.id == 1 }) {
            settings.periodConfigs[idx] = PeriodConfig(id: 1, customName: "", colorIndex: 1, isEnabled: false)
        }
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 25)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule, settings: settings)
        // P1 is disabled — at 8:25 we're before the first enabled period (P2 at 8:55)
        XCTAssertTrue(result.dayState == .beforeSchool || result.dayState == .betweenPeriods)
    }

    // MARK: 1.14 Period progress is clamped to [0, 1]

    func test_periodProgress_isClampedToZeroOne() {
        let atStart = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 0)
        let atEnd   = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 50)

        let r1 = ScheduleEngine.state(for: atStart, schedule: referenceSchedule, settings: makeDefaultSettings())
        let r2 = ScheduleEngine.state(for: atEnd,   schedule: referenceSchedule, settings: makeDefaultSettings())

        if let p1 = r1.currentSlot?.progress { XCTAssertTrue((0.0...1.0).contains(p1)) }
        if let p2 = r2.currentSlot?.progress { XCTAssertTrue((0.0...1.0).contains(p2)) }
    }

    // MARK: 1.15 Period duration is positive

    func test_periodDuration_isPositive() {
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 25)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule, settings: makeDefaultSettings())
        if let slot = result.currentSlot {
            XCTAssertGreaterThan(slot.duration, 0)
        }
    }

    // MARK: 1.16 Display name uses custom name when set

    func test_displayName_usesCustomName() {
        var settings = makeDefaultSettings()
        if let idx = settings.periodConfigs.firstIndex(where: { $0.id == 1 }) {
            settings.periodConfigs[idx] = PeriodConfig(id: 1, customName: "Chemistry", colorIndex: 1, isEnabled: true)
        }
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 25)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule, settings: settings)
        XCTAssertEqual(result.currentSlot?.displayName, "Chemistry")
    }

    // MARK: 1.17 Display name falls back to period name

    func test_displayName_fallsBackToPeriodName() {
        var settings = makeDefaultSettings()
        if let idx = settings.periodConfigs.firstIndex(where: { $0.id == 1 }) {
            settings.periodConfigs[idx] = PeriodConfig(id: 1, customName: "", colorIndex: 1, isEnabled: true)
        }
        let date = makeDate(year: 2026, month: 5, day: 5, hour: 8, minute: 25)
        let result = ScheduleEngine.state(for: date, schedule: referenceSchedule, settings: settings)
        XCTAssertEqual(result.currentSlot?.displayName, "Period 1")
    }

    // MARK: 1.18 Break and Lunch are visible even without PeriodConfig

    func test_breakAndLunch_visibleWithoutConfig() {
        // Break: 9:45–9:55
        let breakDate = makeDate(year: 2026, month: 5, day: 5, hour: 9, minute: 48)
        let breakResult = ScheduleEngine.state(for: breakDate, schedule: referenceSchedule,
                                               settings: makeDefaultSettings())
        XCTAssertNil(breakResult.currentSlot?.config)
        XCTAssertEqual(breakResult.currentSlot?.period.name, "Break")

        // Lunch: 11:45–12:15
        let lunchDate = makeDate(year: 2026, month: 5, day: 5, hour: 12, minute: 0)
        let lunchResult = ScheduleEngine.state(for: lunchDate, schedule: referenceSchedule,
                                               settings: makeDefaultSettings())
        XCTAssertNil(lunchResult.currentSlot?.config)
        XCTAssertEqual(lunchResult.currentSlot?.period.name, "Lunch")
    }
}
