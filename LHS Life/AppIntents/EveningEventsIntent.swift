//
//  EveningEventsIntent.swift
//  LHS Life
//
//  "What's happening this evening" — events on today's LaSalle calendar
//  starting at or after noon. Bell-schedule-category events (e.g. "Block
//  Schedule" banners) are bucketed as a generic count rather than named
//  individually — they're schedule metadata, not "a thing happening".
//  Everything else (athletic, academic, liturgy, professional dress, other)
//  is named individually with its time.
//
//  Reads CalendarStore.shared directly — see NextClassIntent.swift header
//  comment for why this replaced @Dependency.
//

import AppIntents
import SwiftUI

struct EveningEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Happening This Evening"
    static let description = IntentDescription("Tells you what's on the LaSalle calendar this evening.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = CalendarStore.shared
        let settings = UserSettings.shared
        guard settings.accessApproved else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        let now = Date()
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let dayKey = DateFormatter.isoDay.string(from: now)

        let evening = store.events(on: dayKey).filter { $0.startDate >= noon }
        guard !evening.isEmpty else {
            return .result(dialog: "Nothing on the LaSalle calendar this evening.")
        }

        let notable = evening.filter { $0.category != .schedules }
        let bucketedCount = evening.count - notable.count

        guard !notable.isEmpty else {
            // Only bucketed (bell-schedule) items exist — nothing worth naming.
            return .result(dialog: "Nothing notable on the LaSalle calendar this evening.")
        }

        let named = notable.map { "\($0.title) at \(ScheduleEngine.timeString($0.startDate))" }
        let namedList = Self.speakableList(named)

        let dialogText: String
        if bucketedCount > 0 {
            dialogText = "There are a few other things on the calendar, plus \(namedList)."
        } else {
            dialogText = "There's \(namedList)."
        }

        // Snippet shows just the first notable event — keeps the card simple;
        // full list is in the spoken dialog.
        let first = notable[0]
        let view = InfoSnippetView(
            title: first.title,
            symbolName: "moon.stars.fill",
            color: first.category.pillColor,
            detail: ScheduleEngine.timeString(first.startDate)
        )

        return .result(dialog: IntentDialog(stringLiteral: dialogText), view: view)
    }

    /// "A" / "A and B" / "A, B, and C"
    private static func speakableList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let allButLast = items.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(items.last!)"
        }
    }
}
