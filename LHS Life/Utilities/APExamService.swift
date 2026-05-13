//
//  APExamService.swift
//  LHS Life
//

import Foundation

enum APExamService {

    // MARK: - State

    enum APExamState {
        case none
        case mine(examName: String, startTime: Date, endTime: Date, config: PeriodConfig?)
        case someoneElses(examName: String, startTime: Date)
    }

    // MARK: - Detection

    static func examState(
        for dayKey: String,
        events: [SchoolEvent],
        settings: UserSettings
    ) -> APExamState {
        guard let exam = apExamEvent(on: dayKey, events: events) else {
            print("[APExam] No AP exam event found for \(dayKey)")
            return .none
        }

        print("[APExam] Found exam: '\(exam.title)' category=\(exam.category) start=\(exam.startDate)")

        let (matched, config) = matchingConfig(examTitle: exam.title, settings: settings)
        if matched {
            print("[APExam] Matched as mine — config: \(config?.displayName ?? "nil")")
            return .mine(examName: exam.title, startTime: exam.startDate, endTime: exam.endDate, config: config)
        } else {
            print("[APExam] No match — showing as someone else's exam")
            return .someoneElses(examName: exam.title, startTime: exam.startDate)
        }
    }

    // MARK: - Event lookup
    // Note: does NOT filter by category — AP events may be miscategorised
    // if their description contains bell schedule keywords.

    static func apExamEvent(on dayKey: String, events: [SchoolEvent]) -> SchoolEvent? {
        let candidates = events.filter { event in
            event.dayKey == dayKey &&
            event.title.lowercased().hasPrefix("ap ")
        }
        print("[APExam] Candidates for \(dayKey): \(candidates.map { "\($0.title) [\($0.category)]" })")
        return candidates.first
    }

    // MARK: - Matching

    /// Returns (matched, the PeriodConfig that matched) so the banner can use the class color.
    static func matchingConfig(examTitle: String, settings: UserSettings) -> (Bool, PeriodConfig?) {
        let title = examTitle.lowercased()
        let enabledConfigs = settings.periodConfigs
            .filter { $0.isEnabled && !$0.customName.trimmingCharacters(in: .whitespaces).isEmpty }

        print("[APExam] Checking against \(enabledConfigs.count) enabled classes:")

        for config in enabledConfigs {
            let tokens = config.customName
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }  // lowered from 4 — catches "lit", "bio", "env"

            print("[APExam]   '\(config.customName)' → tokens: \(tokens)")

            for token in tokens {
                // Whole-word match only — prevents "calculus" matching "pre-calculus".
                // Treats hyphens as word characters so "pre-calculus" doesn't match "calculus".
                let pattern = "(?<![a-z0-9-])\(NSRegularExpression.escapedPattern(for: token))(?![a-z0-9-])"
                let matched = (try? NSRegularExpression(pattern: pattern))
                    .map { $0.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil }
                    ?? false
                if matched {
                    print("[APExam]   ✓ Token '\(token)' whole-word matched in '\(title)'")
                    return (true, config)
                }
            }
        }
        return (false, nil)
    }
}
