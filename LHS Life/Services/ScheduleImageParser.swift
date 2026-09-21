//
//  ScheduleImageParser.swift
//  LHS Life
//
//  Reads a bell schedule that was posted as a PICTURE instead of a table.
//
//  CalendarWiz events normally carry the schedule as text in DESCRIPTION, and
//  BellScheduleParser handles those. But whoever posts them sometimes attaches
//  a screenshot of the table instead — the HTML description is then nothing
//  but an <img> tag. In the 2026-27 feed that has happened exactly once so
//  far, on the Liturgy day (Sep 21), and the result was the worst kind of
//  wrong: the day has no parseable times, so the Professional Dress floor rule
//  filled in a REGULAR schedule and the app confidently showed period times
//  that were off by as much as half an hour on a day when the whole school
//  went to Mass.
//
//  Rather than hard-code that one day's times — there is exactly one sample in
//  180 days, and the file is named "8 AM Start Liturgy Schedule", implying
//  other variants exist — this reads the picture. Vision's text recognition is
//  on-device, needs no entitlement, and a flat table of black text on white is
//  about the easiest thing you can hand it. BellScheduleSource.imageURL in the
//  model has been describing this exact case, unimplemented, since the start.
//
//  If OCR fails or the image is unreachable, nothing is installed and the
//  existing floor rules stand — no worse than before.
//

import Foundation
import OSLog
import Vision
import CoreGraphics
import ImageIO

enum ScheduleImageParser {

    // MARK: - Finding the image

    /// The first <img src> in an event's HTML description, if any.
    static func imageURL(inHTML html: String?) -> URL? {
        guard let html else { return nil }
        guard let match = html.range(of: #"<img[^>]+src="([^"]+)""#, options: .regularExpression) else {
            return nil
        }
        let tag = String(html[match])
        guard let srcRange = tag.range(of: #"src="([^"]+)""#, options: .regularExpression) else { return nil }
        let src = tag[srcRange]
            .replacingOccurrences(of: "src=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
            // CalendarWiz escapes commas in the iCal payload; they survive into
            // the URL of an image whose filename contains one.
            .replacingOccurrences(of: "\\,", with: ",")
        return URL(string: src.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Reading it

    /// Downloads the image and reads its table, or nil if either step fails.
    ///
    /// Results are cached by URL, so a schedule image is read once per device
    /// rather than on every refresh — the picture for a given day never
    /// changes without its URL changing too.
    static func periods(at url: URL, eventID: String) async -> [Period]? {
        if let cached = Cache.load(for: url) { return cached.asPeriods(eventID: eventID) }

        guard let image = await downloadImage(at: url) else { return nil }
        guard let rows = recognizeRows(in: image), !rows.isEmpty else { return nil }

        let parsed = rows.compactMap { ParsedRow(cells: $0) }
        guard parsed.count >= 3 else { return nil }   // a schedule, not a stray caption

        Cache.save(parsed, for: url)
        return parsed.asPeriods(eventID: eventID)
    }

    // MARK: - Download

    private static func downloadImage(at url: URL) async -> CGImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                LHSLogger.parser.error("Schedule image HTTP \(http.statusCode, privacy: .public)")
                return nil
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            // These pictures are small — the Liturgy one is 498×389, and its
            // text is around 11pt. Upscaling before recognition measurably
            // improves how reliably the AM/PM suffix comes through.
            return image.width < 1000 ? (upscaled(image, factor: 3) ?? image) : image
        } catch {
            LHSLogger.parser.error("Schedule image download failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func upscaled(_ image: CGImage, factor: Int) -> CGImage? {
        let w = image.width * factor, h = image.height * factor
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - OCR

    /// Recognized text, reassembled into table rows.
    ///
    /// Vision returns each run of text separately with a bounding box; it has
    /// no concept of a table. Rows are rebuilt by vertical position — anything
    /// whose centre sits within half a line height of another belongs to the
    /// same row — and then ordered left to right, which turns the three
    /// columns back into (name, start, end).
    private static func recognizeRows(in image: CGImage) -> [[String]]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // times and "3rd Period", not prose
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            LHSLogger.parser.error("Vision failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        struct Fragment {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
            let height: CGFloat
        }

        let fragments: [Fragment] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let box = obs.boundingBox
            return Fragment(text: candidate.string.trimmingCharacters(in: .whitespaces),
                            midY: box.midY, minX: box.minX, height: box.height)
        }.filter { !$0.text.isEmpty }

        guard !fragments.isEmpty else { return nil }

        let tolerance = (fragments.map(\.height).reduce(0, +) / CGFloat(fragments.count)) * 0.6
        var rows: [[Fragment]] = []
        // Vision's origin is bottom-left, so descending midY reads top-down.
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let index = rows.firstIndex(where: { abs(($0.first?.midY ?? 0) - fragment.midY) <= tolerance }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text) }
    }

    // MARK: - Row → Period

    fileprivate struct ParsedRow: Codable {
        let name: String
        let startHour: Int, startMinute: Int
        let endHour: Int,   endMinute: Int

        /// A row is a period only if it has a name and two readable times.
        /// Header rows ("Period | Start | End") and the title line fall out
        /// here, which is why no explicit header detection is needed.
        init?(cells: [String]) {
            let times = cells.compactMap { Self.time(from: $0) }
            guard times.count >= 2 else { return nil }
            guard let label = cells.first(where: { Self.time(from: $0) == nil }) else { return nil }
            let cleaned = Self.normalizeName(label)
            guard !cleaned.isEmpty else { return nil }
            name = cleaned
            (startHour, startMinute) = times[0]
            (endHour,   endMinute)   = times[1]
        }

        /// "8:00 AM" / "12:15 PM" / "1:30" → (hour, minute), 24-hour.
        static func time(from raw: String) -> (Int, Int)? {
            let s = raw.uppercased().replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let match = s.range(of: #"^(\d{1,2}):(\d{2})\s*(AM|PM)?$"#, options: .regularExpression)
            else { return nil }
            let body = String(s[match])
            let isPM = body.hasSuffix("PM")
            let isAM = body.hasSuffix("AM")
            let digits = body.replacingOccurrences(of: "AM", with: "")
                .replacingOccurrences(of: "PM", with: "")
                .trimmingCharacters(in: .whitespaces)
                .split(separator: ":").compactMap { Int($0) }
            guard digits.count == 2, (0...23).contains(digits[0]), (0...59).contains(digits[1]) else { return nil }

            var hour = digits[0]
            if isPM, hour < 12 { hour += 12 }
            if isAM, hour == 12 { hour = 0 }
            // No suffix printed: school days start at 6 and end by 6, so an
            // hour below 6 is afternoon. Same rule BellScheduleParser uses on
            // the text tables, which print bare times.
            if !isPM && !isAM && hour < 6 { hour += 12 }
            return (hour, digits[1])
        }

        /// "1st Period" → "Period 1", so the name matches what the text
        /// tables produce. ScheduleEngine.periodNumber only understands
        /// "Period N", and that mapping is what attaches a student's own
        /// class name and colour to the block.
        static func normalizeName(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if let ordinal = lower.range(of: #"^(\d{1,2})(st|nd|rd|th)?\s*period$"#, options: .regularExpression) {
                let digits = lower[ordinal].prefix(while: \.isNumber)
                if let n = Int(digits) { return "Period \(n)" }
            }
            if let period = lower.range(of: #"^period\s*(\d{1,2})$"#, options: .regularExpression) {
                let digits = lower[period].drop(while: { !$0.isNumber })
                if let n = Int(digits) { return "Period \(n)" }
            }
            if let n = Int(trimmed) { return "Period \(n)" }

            switch lower {
            case "break":   return "Break"
            case "lunch":   return "Lunch"
            case "liturgy": return "Liturgy"
            case "mass":    return "Mass"
            case "advisory": return "Advisory"
            case "passing": return "Passing"
            default:
                // Anything else keeps its posted capitalisation — "Rally",
                // "Assembly", "Advising" — rather than being .capitalized,
                // which would turn "1st Period" into "1St Period".
                return trimmed
            }
        }
    }

    // MARK: - Cache

    fileprivate enum Cache {
        private static var directory: URL? {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        }

        private static func file(for url: URL) -> URL? {
            // The URL's last component is unique per posted picture and already
            // filename-shaped; hashing keeps it short and legal regardless.
            let key = String(abs(url.absoluteString.hashValue))
            return directory?.appendingPathComponent("schedule-image-\(key).json")
        }

        static func load(for url: URL) -> [ParsedRow]? {
            guard let file = file(for: url), let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode([ParsedRow].self, from: data)
        }

        static func save(_ rows: [ParsedRow], for url: URL) {
            guard let file = file(for: url), let data = try? JSONEncoder().encode(rows) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }
}

// MARK: - Rows → Periods

private extension Array where Element == ScheduleImageParser.ParsedRow {
    func asPeriods(eventID: String) -> [Period] {
        enumerated().map { index, row in
            Period(
                id: "\(eventID)-img-\(index)",
                name: row.name,
                startTime: DateComponents(hour: row.startHour, minute: row.startMinute),
                endTime: DateComponents(hour: row.endHour, minute: row.endMinute)
            )
        }
    }
}
