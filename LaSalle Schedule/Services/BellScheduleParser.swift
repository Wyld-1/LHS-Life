//
//  BellScheduleParser.swift
//  LaSalle Schedule
//
//  Parses bell schedule data from a CalendarWiz iCal event description.
//
//  Expected format in DESCRIPTION field:
//
//    Regular Schedule | Monday, Tuesday, Friday
//    Regular Schedule (1-7)
//    First Bell @ 7:55AM | 50 minute classes
//    Period\nBegin\nEnd\nTotal          ← column headers (one token per line)
//    0\n6:45\n7:45\n60                  ← data rows (one value per line)
//    1\n8:00\n8:50\n50
//    Break\n9:45\n9:55\n10
//    ...
//

import Foundation

final class BellScheduleParser {

    // MARK: - Entry Point

    func parse(from event: SchoolEvent) -> BellSchedule? {
        guard let description = event.description, !description.isEmpty else { return nil }
        return parseDescription(description, event: event)
    }

    // MARK: - Description Parser

    private func parseDescription(_ text: String, event: SchoolEvent) -> BellSchedule? {
        // Normalize: split into non-empty trimmed lines
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Find the column header row — "Period" marks the start of the table
        guard let headerIndex = lines.firstIndex(where: { $0.lowercased() == "period" }) else {
            return nil
        }

        // Lines before the header give us schedule type + metadata
        let metaLines = Array(lines[..<headerIndex])
        let scheduleType = inferScheduleType(from: metaLines + [event.title])

        // After "Period" we expect "Begin", "End", "Total" as the next three lines,
        // then groups of 4 lines per row: [name, startTime, endTime, duration]
        let afterHeader = Array(lines[(headerIndex + 1)...])

        // Skip "Begin", "End", "Total" column headers if present
        var dataStart = 0
        let columnHeaders = ["begin", "end", "total", "min", "minutes"]
        while dataStart < afterHeader.count &&
              columnHeaders.contains(afterHeader[dataStart].lowercased()) {
            dataStart += 1
        }

        let dataLines = Array(afterHeader[dataStart...])

        // Each period is 4 consecutive lines: name, start, end, duration
        var periods: [Period] = []
        var i = 0
        while i + 3 < dataLines.count {
            let name     = dataLines[i]
            let startStr = dataLines[i + 1]
            let endStr   = dataLines[i + 2]
            // dataLines[i + 3] is duration — we don't need it, but we consume it
            i += 4

            // Skip rows that look like extra headers or garbage
            guard !columnHeaders.contains(name.lowercased()),
                  let startComps = parseTime(startStr),
                  let endComps   = parseTime(endStr) else { continue }

            let period = Period(
                id: "\(event.id)-\(periods.count)",
                name: normalizeName(name),
                startTime: startComps,
                endTime: endComps
            )
            periods.append(period)
        }

        guard !periods.isEmpty else { return nil }

        return BellSchedule(
            id: event.id,
            date: event.startDate,
            scheduleType: scheduleType,
            periods: periods,
            sourceEventID: event.id
        )
    }

    // MARK: - Time Parsing

    /// Parses "8:00", "7:55AM", "12:15", "2:05" etc.
    private func parseTime(_ raw: String) -> DateComponents? {
        // Strip AM/PM suffix if present
        var s = raw.trimmingCharacters(in: .whitespaces)
        var isPM: Bool? = nil
        if s.uppercased().hasSuffix("AM") { isPM = false; s = String(s.dropLast(2)) }
        if s.uppercased().hasSuffix("PM") { isPM = true;  s = String(s.dropLast(2)) }

        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var hour = parts[0], minute = parts[1]

        if let pm = isPM {
            if pm  && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
        } else {
            // No meridiem — school runs ~6AM–4PM; treat hour < 6 as PM
            if hour < 6 { hour += 12 }
        }

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return comps
    }

    // MARK: - Helpers

    private func inferScheduleType(from lines: [String]) -> ScheduleType {
        let combined = lines.joined(separator: " ").lowercased()
        if combined.contains("late start")                            { return .lateStart }
        if combined.contains("early release") ||
           combined.contains("early dismissal")                       { return .earlyRelease }
        if combined.contains("block")                                 { return .block }
        if combined.contains("assembly")                              { return .assembly }
        if combined.contains("regular")                               { return .regular }
        return .unknown
    }

    private func normalizeName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "break":    return "Break"
        case "lunch":    return "Lunch"
        case "advisory": return "Advisory"
        case "passing":  return "Passing"
        default:
            // "0", "1" … "7" → "Period 0", "Period 1" …
            if let _ = Int(raw) { return "Period \(raw)" }
            return raw.capitalized
        }
    }
}
