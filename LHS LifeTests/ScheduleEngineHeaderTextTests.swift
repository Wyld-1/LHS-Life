//
//  ScheduleEngineHeaderTextTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class ScheduleEngineHeaderTextTests: XCTestCase {

    // Helpers: build an ActiveSlot with a specific endDate so timeRemaining
    // is approximately the requested value when the test executes.
    private func makeSlot(name: String, secondsRemaining: TimeInterval) -> ScheduleEngine.ActiveSlot {
        let start = Date() - 60
        let end   = Date() + secondsRemaining
        let period = Period(id: "t", name: name, startTime: DateComponents(), endTime: DateComponents())
        return ScheduleEngine.ActiveSlot(period: period, config: nil, startDate: start, endDate: end)
    }

    private func makeSlotWithConfig(name: String, customName: String, secondsRemaining: TimeInterval) -> ScheduleEngine.ActiveSlot {
        let start  = Date() - 60
        let end    = Date() + secondsRemaining
        let period = Period(id: "t", name: name, startTime: DateComponents(), endTime: DateComponents())
        let config = PeriodConfig(id: 1, customName: customName, colorIndex: 0, isEnabled: true)
        return ScheduleEngine.ActiveSlot(period: period, config: config, startDate: start, endDate: end)
    }

    // MARK: 2.1 inSession text format

    func test_inSession_textFormat() {
        let slot  = makeSlotWithConfig(name: "Period 1", customName: "Chemistry", secondsRemaining: 2520)
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: slot, nextSlot: nil, dayState: .inSession)
        let text  = ScheduleEngine.headerPrimaryText(for: state)
        XCTAssertEqual(text, "42 min left in Chemistry")
    }

    // MARK: 2.2 inSession rounds up partial minutes

    func test_inSession_roundsUpPartialMinutes() {
        let slot  = makeSlotWithConfig(name: "Period 1", customName: "Chemistry", secondsRemaining: 2521)
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: slot, nextSlot: nil, dayState: .inSession)
        let text  = ScheduleEngine.headerPrimaryText(for: state)
        XCTAssertEqual(text, "43 min left in Chemistry")
    }

    // MARK: 2.3 afterSchool text

    func test_afterSchool_text() {
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: nil, nextSlot: nil, dayState: .afterSchool)
        XCTAssertEqual(ScheduleEngine.headerPrimaryText(for: state), "School's out")
    }

    // MARK: 2.4 noSchedule text

    func test_noSchedule_text() {
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: nil, nextSlot: nil, dayState: .noSchedule)
        XCTAssertEqual(ScheduleEngine.headerPrimaryText(for: state), "No schedule today")
    }

    // MARK: 2.5 holiday text

    func test_holiday_text() {
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: nil, nextSlot: nil, dayState: .holiday)
        XCTAssertEqual(ScheduleEngine.headerPrimaryText(for: state), "No school today")
    }

    // MARK: 2.6 pathwaysDay text

    func test_pathwaysDay_text() {
        let state = ScheduleEngine.ScheduleState(date: Date(), currentSlot: nil, nextSlot: nil, dayState: .pathwaysDay)
        XCTAssertEqual(ScheduleEngine.headerPrimaryText(for: state), "Pathways Day — off campus")
    }

    // MARK: 2.7 headerSecondaryText includes next period name

    func test_secondaryText_includesNextPeriodName() {
        let current = makeSlot(name: "Period 1", secondsRemaining: 1200)
        let next    = makeSlotWithConfig(name: "Period 2", customName: "Lunch", secondsRemaining: 3600)
        let state   = ScheduleEngine.ScheduleState(date: Date(), currentSlot: current, nextSlot: next, dayState: .inSession)
        let text    = ScheduleEngine.headerSecondaryText(for: state)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Next: Lunch"), "Expected 'Next: Lunch' in '\(text!)'")
    }

    // MARK: 2.8 headerSecondaryText nil when no next slot

    func test_secondaryText_nilWhenNoNextSlot() {
        let current = makeSlot(name: "Period 7", secondsRemaining: 600)
        let state   = ScheduleEngine.ScheduleState(date: Date(), currentSlot: current, nextSlot: nil, dayState: .inSession)
        XCTAssertNil(ScheduleEngine.headerSecondaryText(for: state))
    }
}
