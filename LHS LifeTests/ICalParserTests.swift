//
//  ICalParserTests.swift
//  LHS LifeTests
//

import XCTest
@testable import LHS_Life

final class ICalParserTests: XCTestCase {

    private func makeCalendar(_ vevent: String) -> String {
        "BEGIN:VCALENDAR\r\n\(vevent)\r\nEND:VCALENDAR"
    }

    private func makeVEvent(_ props: String) -> String {
        "BEGIN:VEVENT\r\n\(props)\r\nEND:VEVENT"
    }

    private func parse(_ raw: String) throws -> [SchoolEvent] {
        try ICalParser.parse(raw)
    }

    // MARK: 3.1 Minimal VEVENT

    func test_minimalVEvent_parsed() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:test-uid-1\r\nSUMMARY:Regular Schedule\r\nDTSTART:20260505\r\nDTEND:20260505"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "test-uid-1")
        XCTAssertEqual(events[0].title, "Regular Schedule")
        XCTAssertTrue(events[0].isAllDay)
    }

    // MARK: 3.2 Timed event (floating Pacific)

    func test_timedEvent_parsed() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:timed-1\r\nSUMMARY:Timed\r\nDTSTART:20260505T080000\r\nDTEND:20260505T085000"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isAllDay)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let comps = cal.dateComponents([.hour, .minute], from: events[0].startDate)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: 3.3 UTC datetime

    func test_utcDatetime_parsed() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:utc-1\r\nSUMMARY:UTC Event\r\nDTSTART:20260505T150000Z\r\nDTEND:20260505T160000Z"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isAllDay)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let comps = utcCal.dateComponents([.hour, .minute], from: events[0].startDate)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 0)
    }

    // MARK: 3.4 Line unfolding

    func test_lineUnfolding_joinsLines() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:fold-1\r\nSUMMARY:This is a very long summ\r\n ary that is folded\r\nDTSTART:20260505"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events[0].title, "This is a very long summary that is folded")
    }

    // MARK: 3.5 TZID parameter stripped from key

    func test_tzidParameter_parsedSuccessfully() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:tzid-1\r\nSUMMARY:TZID Event\r\nDTSTART;TZID=America/Los_Angeles:20260505T080000\r\nDTEND:20260505T090000"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isAllDay)
    }

    // MARK: 3.6 Text unescaping

    func test_textUnescaping_handlesEscapeSequences() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:escape-1\r\nSUMMARY:Chemistry\\, AP\\nSecond line\\;done\r\nDTSTART:20260505"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events[0].title, "Chemistry, AP\nSecond line;done")
    }

    // MARK: 3.7 Missing UID returns no event

    func test_missingUID_returnsNoEvent() throws {
        let raw = makeCalendar(makeVEvent(
            "SUMMARY:No UID\r\nDTSTART:20260505"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 0)
    }

    // MARK: 3.8 Missing SUMMARY returns no event

    func test_missingSummary_returnsNoEvent() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:no-summary-1\r\nDTSTART:20260505"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 0)
    }

    // MARK: 3.9 Missing DTSTART returns no event

    func test_missingDTSTART_returnsNoEvent() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:no-start-1\r\nSUMMARY:No start"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events.count, 0)
    }

    // MARK: 3.10 Multiple VEVENTs

    func test_multipleVEvents_allParsed() throws {
        let e1 = makeVEvent("UID:uid-1\r\nSUMMARY:Event 1\r\nDTSTART:20260505")
        let e2 = makeVEvent("UID:uid-2\r\nSUMMARY:Event 2\r\nDTSTART:20260506")
        let e3 = makeVEvent("UID:uid-3\r\nSUMMARY:Event 3\r\nDTSTART:20260507")
        let raw = makeCalendar("\(e1)\r\n\(e2)\r\n\(e3)")
        let events = try parse(raw)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Set(events.map(\.id)), ["uid-1", "uid-2", "uid-3"])
    }

    // MARK: 3.11 LOCATION parsed correctly

    func test_location_parsedCorrectly() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:loc-1\r\nSUMMARY:Hotel Event\r\nDTSTART:20260505\r\nLOCATION:Red Lion Hotel"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events[0].location, "Red Lion Hotel")
    }

    // MARK: 3.12 DESCRIPTION with iCal escape sequences

    func test_description_escapedCorrectly() throws {
        let raw = makeCalendar(makeVEvent(
            "UID:desc-1\r\nSUMMARY:Desc Test\r\nDTSTART:20260505\r\nDESCRIPTION:Math HW\\nChapter 4\\, problems 1-10"
        ))
        let events = try parse(raw)
        XCTAssertEqual(events[0].description, "Math HW\nChapter 4, problems 1-10")
    }
}
