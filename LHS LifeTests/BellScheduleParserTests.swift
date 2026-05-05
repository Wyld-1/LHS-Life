//
//  BellScheduleParserTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class BellScheduleParserTests: XCTestCase {

    private let parser = BellScheduleParser()

    // Reference description matching the exact CalendarWiz format
    private let referenceDescription = """
        Regular Schedule | Monday, Tuesday, Friday
        Regular Schedule (1-7)
        First Bell @ 7:55AM | 50 minute classes
        Period
        Begin
        End
        Total
        0
        6:45
        7:45
        60
        1
        8:00
        8:50
        50
        Break
        9:45
        9:55
        10
        3
        10:00
        10:50
        50
        Lunch
        11:45
        12:15
        30
        """

    private func makeEvent(description: String?, title: String = "Regular Schedule") -> SchoolEvent {
        SchoolEvent(id: "test-event", title: title,
                    startDate: makeDate(year: 2026, month: 5, day: 5, hour: 0, minute: 0),
                    endDate: makeDate(year: 2026, month: 5, day: 5, hour: 0, minute: 0),
                    isAllDay: true, location: nil, description: description,
                    url: nil, category: .bellSchedule)
    }

    // MARK: 4.1 Parses all periods from reference description

    func test_referenceDescription_parsesAllPeriods() {
        let event = makeEvent(description: referenceDescription)
        let schedule = parser.parse(from: event)
        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule?.periods.count, 5)
        XCTAssertEqual(schedule?.periods[0].name, "Period 0")
        XCTAssertEqual(schedule?.periods[1].name, "Period 1")
        XCTAssertEqual(schedule?.periods[2].name, "Break")
        XCTAssertEqual(schedule?.periods[3].name, "Period 3")
        XCTAssertEqual(schedule?.periods[4].name, "Lunch")
    }

    // MARK: 4.2 Period start times parsed correctly

    func test_startTimes_parsedCorrectly() {
        let event = makeEvent(description: referenceDescription)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let p1    = schedule.periods.first { $0.name == "Period 1" }
        let brk   = schedule.periods.first { $0.name == "Break" }
        let lunch = schedule.periods.first { $0.name == "Lunch" }
        XCTAssertEqual(p1?.startTime.hour, 8);    XCTAssertEqual(p1?.startTime.minute, 0)
        XCTAssertEqual(brk?.startTime.hour, 9);   XCTAssertEqual(brk?.startTime.minute, 45)
        XCTAssertEqual(lunch?.startTime.hour, 11); XCTAssertEqual(lunch?.startTime.minute, 45)
    }

    // MARK: 4.3 Period end times parsed correctly

    func test_endTimes_parsedCorrectly() {
        let event = makeEvent(description: referenceDescription)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let p1    = schedule.periods.first { $0.name == "Period 1" }
        let lunch = schedule.periods.first { $0.name == "Lunch" }
        XCTAssertEqual(p1?.endTime.hour, 8);     XCTAssertEqual(p1?.endTime.minute, 50)
        XCTAssertEqual(lunch?.endTime.hour, 12); XCTAssertEqual(lunch?.endTime.minute, 15)
    }

    // MARK: 4.4 Duration computed correctly

    func test_duration_computedCorrectly() {
        let event = makeEvent(description: referenceDescription)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let p1    = schedule.periods.first { $0.name == "Period 1" }
        let lunch = schedule.periods.first { $0.name == "Lunch" }
        XCTAssertEqual(p1?.durationMinutes, 50)
        XCTAssertEqual(lunch?.durationMinutes, 30)
    }

    // MARK: 4.5 Schedule type inferred as regular

    func test_scheduleType_regular() {
        let event = makeEvent(description: referenceDescription, title: "Regular Schedule")
        XCTAssertEqual(parser.parse(from: event)?.scheduleType, .regular)
    }

    // MARK: 4.6 Schedule type inferred as lateStart

    func test_scheduleType_lateStart() {
        let desc = "Late Start Schedule\nPeriod\nBegin\nEnd\nTotal\n1\n9:30\n10:20\n50"
        let event = makeEvent(description: desc, title: "Late Start Schedule")
        XCTAssertEqual(parser.parse(from: event)?.scheduleType, .lateStart)
    }

    // MARK: 4.7 Schedule type inferred as block

    func test_scheduleType_block() {
        let desc = "Block Schedule\nPeriod\nBegin\nEnd\nTotal\n1\n8:00\n9:30\n90"
        let event = makeEvent(description: desc, title: "Block Schedule")
        XCTAssertEqual(parser.parse(from: event)?.scheduleType, .block)
    }

    // MARK: 4.8 Schedule type inferred as earlyRelease

    func test_scheduleType_earlyRelease() {
        let desc = "Early Release\nPeriod\nBegin\nEnd\nTotal\n1\n8:00\n8:35\n35"
        let event = makeEvent(description: desc, title: "Early Release")
        XCTAssertEqual(parser.parse(from: event)?.scheduleType, .earlyRelease)
    }

    // MARK: 4.9 PM times without meridiem suffix (hour < 6 → +12)

    func test_pmTimesWithoutSuffix_inferredCorrectly() {
        let desc = "Regular Schedule\nPeriod\nBegin\nEnd\nTotal\n6\n1:15\n2:05\n50"
        let event = makeEvent(description: desc)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let p6 = schedule.periods.first { $0.name == "Period 6" }
        XCTAssertEqual(p6?.startTime.hour, 13)
        XCTAssertEqual(p6?.startTime.minute, 15)
    }

    // MARK: 4.10 Times with AM suffix

    func test_amSuffix_parsedCorrectly() {
        let desc = "Regular Schedule\nPeriod\nBegin\nEnd\nTotal\n0\n7:55AM\n8:45AM\n50"
        let event = makeEvent(description: desc)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let p0 = schedule.periods.first { $0.name == "Period 0" }
        XCTAssertEqual(p0?.startTime.hour, 7)
        XCTAssertEqual(p0?.startTime.minute, 55)
    }

    // MARK: 4.11 Returns nil when no "Period" header found

    func test_noPeriodHeader_returnsNil() {
        let event = makeEvent(description: "Just some random text without the header.")
        XCTAssertNil(parser.parse(from: event))
    }

    // MARK: 4.12 Returns nil when description is nil

    func test_nilDescription_returnsNil() {
        let event = makeEvent(description: nil)
        XCTAssertNil(parser.parse(from: event))
    }

    // MARK: 4.13 Returns nil when description is empty

    func test_emptyDescription_returnsNil() {
        let event = makeEvent(description: "")
        XCTAssertNil(parser.parse(from: event))
    }

    // MARK: 4.14 Period names normalized

    func test_periodNamesNormalized() {
        // "0" → "Period 0", "break" → "Break", "lunch" → "Lunch", "ADVISORY" → "Advisory"
        let desc = """
            Regular Schedule
            Period
            Begin
            End
            Total
            0
            6:45
            7:45
            60
            break
            9:45
            9:55
            10
            lunch
            11:45
            12:15
            30
            ADVISORY
            2:10
            2:40
            30
            """
        let event = makeEvent(description: desc)
        guard let schedule = parser.parse(from: event) else { return XCTFail("nil schedule") }
        let names = schedule.periods.map(\.name)
        XCTAssertTrue(names.contains("Period 0"))
        XCTAssertTrue(names.contains("Break"))
        XCTAssertTrue(names.contains("Lunch"))
        XCTAssertTrue(names.contains("Advisory"))
    }
}
