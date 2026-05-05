//
//  TestHelpers.swift
//  LHS LifeTests
//

import Foundation
import XCTest
@testable import LHS_Life

// MARK: - Date construction

/// Builds a Date at a specific time on a specific day in Pacific time.
func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return cal.date(from: comps)!
}

// MARK: - Bell schedule construction

/// Builds a Period with the given name and 24-hour start/end times.
func makePeriod(id: String = "test", name: String, startH: Int, startM: Int, endH: Int, endM: Int) -> Period {
    var start = DateComponents(); start.hour = startH; start.minute = startM
    var end   = DateComponents(); end.hour   = endH;   end.minute   = endM
    return Period(id: id, name: name, startTime: start, endTime: end)
}

/// Builds a BellSchedule on the given date with the provided periods.
func makeSchedule(on date: Date, periods: [Period], type: ScheduleType = .regular) -> BellSchedule {
    BellSchedule(id: "test-schedule", date: date, scheduleType: type,
                 periods: periods, sourceEventID: "test-event")
}

/// Standard LaSalle reference schedule used by all ScheduleEngineTests.
/// Period order by start time: P1, P2, Break, P3, P4, Lunch, P5, P6, P7.
let referenceDate = makeDate(year: 2026, month: 5, day: 5, hour: 0, minute: 0)

let referenceSchedule: BellSchedule = makeSchedule(on: referenceDate, periods: [
    makePeriod(id: "p1",  name: "Period 1", startH: 8,  startM: 0,  endH: 8,  endM: 50),
    makePeriod(id: "p2",  name: "Period 2", startH: 8,  startM: 55, endH: 9,  endM: 45),
    makePeriod(id: "brk", name: "Break",    startH: 9,  startM: 45, endH: 9,  endM: 55),
    makePeriod(id: "p3",  name: "Period 3", startH: 10, startM: 0,  endH: 10, endM: 50),
    makePeriod(id: "p4",  name: "Period 4", startH: 10, startM: 55, endH: 11, endM: 45),
    makePeriod(id: "lun", name: "Lunch",    startH: 11, startM: 45, endH: 12, endM: 15),
    makePeriod(id: "p5",  name: "Period 5", startH: 12, startM: 20, endH: 13, endM: 10),
    makePeriod(id: "p6",  name: "Period 6", startH: 13, startM: 15, endH: 14, endM: 5),
    makePeriod(id: "p7",  name: "Period 7", startH: 14, startM: 10, endH: 15, endM: 0),
])

/// Builds a UserSettings with all periods 1–7 enabled and no custom names.
func makeDefaultSettings() -> UserSettings {
    UserSettings()
}

/// Builds a minimal SchoolEvent.
func makeEvent(
    id: String = "evt-1",
    title: String,
    startDate: Date,
    endDate: Date? = nil,
    isAllDay: Bool = false,
    location: String? = nil,
    description: String? = nil,
    category: EventCategory = .other
) -> SchoolEvent {
    SchoolEvent(id: id, title: title, startDate: startDate,
                endDate: endDate ?? startDate, isAllDay: isAllDay,
                location: location, description: description,
                url: nil, category: category)
}
