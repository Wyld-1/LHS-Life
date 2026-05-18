//
//  ICalParser.swift
//  LaSalle Schedule
//
//  RFC 5545 iCalendar parser — hand-rolled, zero dependencies.
//  Handles line unfolding, VEVENT extraction, and date parsing
//  for both DATE-TIME (with/without TZID) and DATE (all-day) values.
//

import Foundation

enum ICalParser {

    // MARK: - Entry Point

    static func parse(_ raw: String) throws -> [SchoolEvent] {
        let lines = unfold(raw)
        var events: [SchoolEvent] = []
        var currentBlock: [String: String]? = nil

        for line in lines {
            if line == "BEGIN:VEVENT" {
                currentBlock = [:]
            } else if line == "END:VEVENT" {
                if let block = currentBlock, let event = buildEvent(from: block) {
                    events.append(event)
                }
                currentBlock = nil
            } else if currentBlock != nil {
                // iCal properties can have parameters: DTSTART;TZID=America/Los_Angeles:20260507T080000
                // We split on the first ':' after stripping parameters for the key.
                let (key, value) = splitProperty(line)
                currentBlock?[key] = value
            }
        }

        return events
    }

    // MARK: - Line Unfolding (RFC 5545 §3.1)

    /// iCal folds long lines by inserting CRLF + whitespace. Unfold them.
    private static func unfold(_ raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r",   with: "\n")
        var result: [String] = []
        var current = ""
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && !current.isEmpty {
                current += line.dropFirst()
            } else {
                if !current.isEmpty { result.append(current) }
                current = line
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Property Splitting

    /// Returns (bareKey, value). Strips TZID and other parameters from the key.
    /// e.g. "DTSTART;TZID=America/Los_Angeles:20260507T080000" → ("DTSTART", "20260507T080000")
    private static func splitProperty(_ line: String) -> (String, String) {
        guard let colonIdx = line.firstIndex(of: ":") else { return (line, "") }
        let keyPart = String(line[line.startIndex..<colonIdx])
        let value   = String(line[line.index(after: colonIdx)...])
        // Strip parameters (everything after first ';')
        let bareKey = keyPart.components(separatedBy: ";").first ?? keyPart
        return (bareKey.uppercased(), value)
    }

    // MARK: - Event Builder

    private static func buildEvent(from block: [String: String]) -> SchoolEvent? {
        guard
            let uid   = block["UID"],
            let title = block["SUMMARY"].map({ unescape($0) }),
            let dtStart = block["DTSTART"].flatMap({ parseDate($0) })
        else { return nil }

        let dtEnd = block["DTEND"].flatMap { parseDate($0) } ?? dtStart
        let isAllDay = block["DTSTART"].map { !$0.contains("T") } ?? false
        let description     = block["DESCRIPTION"].map    { unescape($0) }
        let htmlDescription = block["X-ALT-DESC"].map     { unescape($0) }
        let location        = block["LOCATION"].map        { unescape($0) }
        let urlString       = block["URL"]
        let url             = urlString.flatMap { URL(string: $0) }

        return SchoolEvent(
            id: uid,
            title: title,
            startDate: dtStart,
            endDate: dtEnd,
            isAllDay: isAllDay,
            location: location,
            description: description,
            htmlDescription: htmlDescription,
            url: url,
            category: BellScheduleDetector.category(title: title, description: description)
        )
    }

    // MARK: - Date Parsing

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let localTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    /// Parses iCal date strings:
    /// - "20260507"            → all-day
    /// - "20260507T083000"     → floating local time (we assume Pacific)
    /// - "20260507T083000Z"    → UTC
    private static func parseDate(_ value: String) -> Date? {
        let v = value.trimmingCharacters(in: .whitespaces)

        if v.count == 8 {
            // DATE only — all day
            return DateComponents.isoDate(from: v, timeZone: localTimeZone)
        } else if v.hasSuffix("Z") && v.count == 16 {
            // UTC datetime
            return DateComponents.isoDateTime(from: String(v.dropLast()), timeZone: TimeZone(identifier: "UTC")!)
        } else if v.count == 15 {
            // Floating — assume Pacific
            return DateComponents.isoDateTime(from: v, timeZone: localTimeZone)
        }
        return nil
    }

    // MARK: - Text Unescaping

    /// iCal escapes commas, semicolons, backslashes, and \n literals.
    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n",  with: "\n")
            .replacingOccurrences(of: "\\,",  with: ",")
            .replacingOccurrences(of: "\\;",  with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - DateComponents helpers

private extension DateComponents {
    static func isoDate(from s: String, timeZone: TimeZone) -> Date? {
        guard s.count == 8 else { return nil }
        var comps = DateComponents()
        comps.year   = Int(s.prefix(4))
        comps.month  = Int(s.dropFirst(4).prefix(2))
        comps.day    = Int(s.dropFirst(6).prefix(2))
        comps.hour = 0; comps.minute = 0; comps.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: comps)
    }

    static func isoDateTime(from s: String, timeZone: TimeZone) -> Date? {
        guard s.count == 15 else { return nil }
        // "20260507T083000"
        let datePart = String(s.prefix(8))
        let timePart = String(s.dropFirst(9))
        var comps = DateComponents()
        comps.year   = Int(datePart.prefix(4))
        comps.month  = Int(datePart.dropFirst(4).prefix(2))
        comps.day    = Int(datePart.dropFirst(6).prefix(2))
        comps.hour   = Int(timePart.prefix(2))
        comps.minute = Int(timePart.dropFirst(2).prefix(2))
        comps.second = Int(timePart.dropFirst(4).prefix(2))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: comps)
    }
}
