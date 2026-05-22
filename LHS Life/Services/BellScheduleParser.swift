//
//  BellScheduleParser+FinalExamParser.swift
//  LHS Life
//
//  BellScheduleParser — parses regular/block/etc schedules from plain-text DESCRIPTION.
//  FinalExamParser    — parses the multi-column HTML finals table from X-ALT-DESC.
//

import Foundation

enum FinalExamParser {

    // MARK: - Regular Schedule Factory

    /// Standard La Salle regular schedule periods.
    /// Used as a fallback when a student has no finals on a seniors-only finals day.
    static func regularPeriods(for date: Date, sourceID: String) -> [Period] {
        func t(_ h: Int, _ m: Int) -> DateComponents {
            var c = DateComponents(); c.hour = h; c.minute = m; return c
        }
        return [
            Period(id: "\(sourceID)-reg-0",     name: "Period 0", startTime: t(6,45),  endTime: t(7,45)),
            Period(id: "\(sourceID)-reg-1",     name: "Period 1", startTime: t(8,0),   endTime: t(8,50)),
            Period(id: "\(sourceID)-reg-2",     name: "Period 2", startTime: t(8,55),  endTime: t(9,45)),
            Period(id: "\(sourceID)-reg-break", name: "Break",    startTime: t(9,45),  endTime: t(9,55)),
            Period(id: "\(sourceID)-reg-3",     name: "Period 3", startTime: t(10,0),  endTime: t(10,50)),
            Period(id: "\(sourceID)-reg-4",     name: "Period 4", startTime: t(10,55), endTime: t(11,45)),
            Period(id: "\(sourceID)-reg-lunch", name: "Lunch",    startTime: t(11,45), endTime: t(12,15)),
            Period(id: "\(sourceID)-reg-5",     name: "Period 5", startTime: t(12,20), endTime: t(13,10)),
            Period(id: "\(sourceID)-reg-6",     name: "Period 6", startTime: t(13,15), endTime: t(14,5)),
            Period(id: "\(sourceID)-reg-7",     name: "Period 7", startTime: t(14,10), endTime: t(15,0)),
        ]
    }

    // MARK: - Entry Point

    /// Parses ALL day columns from the finals HTML table, returning one BellSchedule per day.
    /// Each iCal event embeds the full multi-day table — we extract every column
    /// so a single event (e.g. Wed’s “Final Exams 1&2”) also populates Tue, Thu, Fri.
    static func parseAll(html: String, event: SchoolEvent, graduationYear: Int? = nil) -> [BellSchedule] {
        let rows = extractRows(from: html)
        guard rows.count >= 3 else { return [] }
        let headerRow = rows[0]
        var results: [BellSchedule] = []

        for (colIndex, headerCell) in headerRow.enumerated() {
            guard let date = dateFromHeader(headerCell) else { continue }

            if let gradYear = graduationYear {
                let label     = headerCell.lowercased()
                let isSenior  = PathwaysService.schoolYear(for: date) + 1 == gradYear
                let hasFrosh  = label.contains("frosh") || label.contains("fresh")
                let hasJunior = label.contains("junior")
                let hasSenior = label.contains("senior")
                let isSeniorsOnly = hasSenior && !hasFrosh && !hasJunior

                if isSeniorsOnly && !isSenior {
                    // Non-senior on a seniors-only day: synthesize a regular schedule
                    let dayKey = DateFormatter.isoDay.string(from: date)
                    results.append(BellSchedule(
                        id: "regular-\(dayKey)",
                        date: date,
                        scheduleType: .regular,
                        periods: FinalExamParser.regularPeriods(for: date, sourceID: event.id),
                        sourceEventID: event.id
                    ))
                    continue
                }
                if (hasFrosh || hasJunior) && !hasSenior && isSenior {
                    continue  // Senior on a frosh-junior day: skip
                }
            }

            var periods: [Period] = []
            for row in rows.dropFirst(2) {
                let (timeStr, periodName) = extractPeriod(from: row, dayColIndex: colIndex)
                guard let name = periodName, !name.isEmpty,
                      !isNoise(name),
                      let (start, end) = parseTimeRange(timeStr)
                else { continue }
                periods.append(Period(
                    id: "\(event.id)-col\(colIndex)-\(periods.count)",
                    name: normalizeName(name),
                    startTime: start,
                    endTime: end
                ))
            }
            guard !periods.isEmpty else { continue }

            let dayKey = DateFormatter.isoDay.string(from: date)
            results.append(BellSchedule(
                id: "\(event.id)-\(dayKey)",
                date: date,
                scheduleType: .finals,
                periods: periods,
                sourceEventID: event.id
            ))
        }
        return results
    }

    /// Extracts a concrete Date from a header cell like “Tues., May 26 Seniors”.
    /// Returns nil for empty, whitespace-only, or time-only cells.
    private static func dateFromHeader(_ cell: String) -> Date? {
        let lower = cell.lowercased()
        let monthMap: [String: Int] = [
            "jan":1,"feb":2,"mar":3,"apr":4,"may":5,"jun":6,
            "jul":7,"aug":8,"sep":9,"oct":10,"nov":11,"dec":12
        ]
        guard let month = monthMap.first(where: { lower.contains($0.key) })?.value else { return nil }
        let words = cell.components(separatedBy: CharacterSet(charactersIn: " .,\t\n"))
        guard let day = words.compactMap({ Int($0) }).first else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = 0; comps.minute = 0; comps.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal.date(from: comps)
    }

    // MARK: - HTML Table Extraction

    /// Returns array of rows, each row is array of cell text strings.
    private static func extractRows(from html: String) -> [[String]] {
        // Split on <tr> tags
        let rowPattern = #"(?i)<tr[^>]*>(.*?)</tr>"#
        let cellPattern = #"(?i)<t[dh][^>]*>(.*?)</t[dh]>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators])
        else { return [] }

        let nsHtml = html as NSString
        let rowMatches = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        return rowMatches.map { rowMatch in
            let rowContent = nsHtml.substring(with: rowMatch.range(at: 1))
            let cellMatches = cellRegex.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent))
            return cellMatches.map { cellMatch in
                let cellContent = (rowContent as NSString).substring(with: cellMatch.range(at: 1))
                return stripHTML(cellContent).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Strip HTML tags and decode entities.
    private static func stripHTML(_ html: String) -> String {
        var s = html
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
        // Collapse whitespace
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Period Extraction

    /// Given a table row and the target day column index, return (timeStr, periodName).
    /// The time column for a given day column is:
    ///   - day col 1 (Tuesday)  → time col 0
    ///   - day col 3+ (Wed–Fri) → time col 2
    private static func extractPeriod(from row: [String], dayColIndex: Int) -> (String, String?) {
        let timeColIndex = dayColIndex <= 1 ? 0 : 2
        let timeStr = row.indices.contains(timeColIndex) ? row[timeColIndex] : ""
        let period  = row.indices.contains(dayColIndex)  ? row[dayColIndex]  : nil
        return (timeStr, period)
    }

    // MARK: - Time Range Parsing

    /// Parses "8:00-9:25" → (start: DateComponents, end: DateComponents)
    private static func parseTimeRange(_ raw: String) -> (DateComponents, DateComponents)? {
        // Handle both – (en dash) and - (hyphen)
        let parts = raw
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .split(separator: "-", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = parseTime(parts[0]),
              let end   = parseTime(parts[1])
        else { return nil }
        return (start, end)
    }

    private static func parseTime(_ raw: String) -> DateComponents? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var isPM: Bool? = nil
        if s.uppercased().hasSuffix("AM") { isPM = false; s = String(s.dropLast(2)) }
        if s.uppercased().hasSuffix("PM") { isPM = true;  s = String(s.dropLast(2)) }

        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        var hour = p[0], minute = p[1]

        if let pm = isPM {
            if pm  && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
        } else {
            if hour < 6 { hour += 12 }  // school runs 6am–4pm
        }
        var comps = DateComponents()
        comps.hour = hour; comps.minute = minute
        return comps
    }

    // MARK: - Helpers

    private static func isNoise(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.isEmpty
            || lower == "&nbsp;"
            || lower.contains("warning bell")
            || lower.contains("senior dismissal")
            || lower.contains("senior present")
            || lower.contains("dismissal")
    }

    private static func normalizeName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower == "break"  { return "Break" }
        if lower == "lunch"  { return "Lunch" }
        // "Period 1", "Period 2", etc. pass through as-is
        return raw
    }
}

// MARK: - BellScheduleParser

final class BellScheduleParser {

    // MARK: - Entry Point

    func parse(from event: SchoolEvent, graduationYear: Int? = nil) -> [BellSchedule] {
        // Senior Presentation day — CalendarWiz has no machine-readable bell schedule
        // in the description. Detect by title and inject the hardcoded grade-specific
        // schedule. This check runs BEFORE finals and description parsing so the pro
        // dress floor rule in CalendarStore never fires on this day.
        if event.title.lowercased().contains("senior presentation") {
            if let schedule = seniorPresentationSchedule(on: event.startDate, graduationYear: graduationYear) {
                return [schedule]
            }
            return []
        }

        let titleOrDesc = (event.title + " " + (event.description ?? "")).lowercased()
        let looksLikeFinals = event.title.lowercased().contains("final")
            || titleOrDesc.contains("final exam schedule")
        if let html = event.htmlDescription, looksLikeFinals {
            let schedules = FinalExamParser.parseAll(html: html, event: event, graduationYear: graduationYear)
            if !schedules.isEmpty { return schedules }
        }
        if let schedule = parseSingle(from: event) { return [schedule] }
        return []
    }

    private func parseSingle(from event: SchoolEvent) -> BellSchedule? {
        guard let text = event.description, !text.isEmpty else { return nil }
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
        let hasLiturgy     = combined.contains("liturgy") || combined.contains("mass")
        let hasOdd         = combined.contains("odd")
        let hasEven        = combined.contains("even")
        let hasBlock       = combined.contains("block")
        let hasEarlyRel    = combined.contains("early release") || combined.contains("early dismissal")

        if combined.contains("final exam") || combined.contains("finals") { return .finals }
        if combined.contains("late start")                                 { return .lateStart }
        if hasEarlyRel && hasLiturgy  { return .earlyReleaseLiturgy }
        if hasEarlyRel                { return .earlyRelease }
        if hasOdd  && hasBlock && hasLiturgy { return .oddBlockLiturgy }
        if hasEven && hasBlock && hasLiturgy { return .evenBlockLiturgy }
        if hasOdd  && hasBlock               { return .oddBlock }
        if hasEven && hasBlock               { return .evenBlock }
        if combined.contains("assembly")     { return .assembly }
        if combined.contains("regular") && hasLiturgy { return .regularLiturgy }
        if combined.contains("regular")      { return .regular }
        if hasLiturgy                        { return .regularLiturgy }
        return .unknown
    }

    // MARK: - Senior Presentation Schedule Factory

    /// Returns the hardcoded Senior Presentation day schedule for the user's grade.
    /// Two completely different schedules run simultaneously on this day:
    ///   Seniors:    Short finals day (Periods 5 & 6 exams) ending at 12:10 dismissal.
    ///   9–11 grade: Full compressed 7-period assembly day around the SP block.
    ///
    /// Returns nil only if graduationYear is nil (unknown grade) — caller should
    /// avoid starting a Live Activity in that case.
    private func seniorPresentationSchedule(
        on date: Date,
        graduationYear: Int?
    ) -> BellSchedule? {
        guard let graduationYear else { return nil }
        let dayKey   = DateFormatter.isoDay.string(from: date)
        let isSenior = PathwaysService.schoolYear(for: date) + 1 == graduationYear

        func t(_ h: Int, _ m: Int) -> DateComponents {
            var c = DateComponents(); c.hour = h; c.minute = m; return c
        }

        let periods: [Period]
        if isSenior {
            // Senior Final Exam Schedule
            // Period 5 / 6 are named "Period X Final" so LiveActivityService.buildSchedule
            // can look up the user's configured class name and append " Final".
            periods = [
                Period(id: "\(dayKey)-sp-5f",   name: "Period 5 Final",      startTime: t(8,5),   endTime: t(9,30)),
                Period(id: "\(dayKey)-sp-brk",  name: "Break",              startTime: t(9,30),  endTime: t(9,40)),
                Period(id: "\(dayKey)-sp-6f",   name: "Period 6 Final",      startTime: t(9,45),  endTime: t(11,10)),
                Period(id: "\(dayKey)-sp-pres", name: "Senior Presentation", startTime: t(11,15), endTime: t(12,10)),
            ]
        } else {
            // Assembly Schedule (9–11th grade)
            periods = [
                Period(id: "\(dayKey)-sp-1",    name: "Period 1",            startTime: t(8,5),   endTime: t(8,45)),
                Period(id: "\(dayKey)-sp-2",    name: "Period 2",            startTime: t(8,50),  endTime: t(9,30)),
                Period(id: "\(dayKey)-sp-brk",  name: "Break",              startTime: t(9,30),  endTime: t(9,40)),
                Period(id: "\(dayKey)-sp-3",    name: "Period 3",            startTime: t(9,45),  endTime: t(10,25)),
                Period(id: "\(dayKey)-sp-4",    name: "Period 4",            startTime: t(10,30), endTime: t(11,10)),
                Period(id: "\(dayKey)-sp-pres", name: "Senior Presentation", startTime: t(11,15), endTime: t(12,10)),
                Period(id: "\(dayKey)-sp-lnch", name: "Lunch",              startTime: t(12,10), endTime: t(12,40)),
                Period(id: "\(dayKey)-sp-5",    name: "Period 5",            startTime: t(12,45), endTime: t(13,25)),
                Period(id: "\(dayKey)-sp-6",    name: "Period 6",            startTime: t(13,30), endTime: t(14,10)),
                Period(id: "\(dayKey)-sp-7",    name: "Period 7",            startTime: t(14,20), endTime: t(15,0)),
            ]
        }

        return BellSchedule(
            id: "seniorp-\(dayKey)-\(isSenior ? "senior" : "assembly")",
            date: date,
            scheduleType: .seniorPresentation,
            periods: periods,
            sourceEventID: "senior-presentation"
        )
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
