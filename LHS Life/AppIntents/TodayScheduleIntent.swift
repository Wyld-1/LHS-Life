//
//  TodayScheduleIntent.swift
//  LHS Life
//
//  "What schedule is today" / "is today a block schedule" — reads straight
//  from ScheduleType.scheduleLabel and .pillColor, same source as the
//  in-app schedule pill, so wording and color can't drift out of sync.
//
//  Reads CalendarStore.shared directly — see NextClassIntent.swift header
//  comment for why this replaced @Dependency.
//

import AppIntents
import SwiftUI

struct TodayScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "What Schedule Is Today"
    static let description = IntentDescription("Tells you what kind of bell schedule is running today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = CalendarStore.shared
        let settings = UserSettings.shared
        guard settings.accessApproved else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        let dayKey = DateFormatter.isoDay.string(from: Date())
        guard let schedule = store.bellSchedule(for: dayKey) else {
            return .result(dialog: "There's no bell schedule loaded for today.")
        }

        let type = schedule.scheduleType
        let label = type.scheduleLabel
        // "Today is Finals." / "Today is Senior Presentation." read fine without
        // an article; everything else needs "a"/"an". Flag for review — this is
        // the one spot doing its own grammar rather than reusing existing copy.
        let dialogText: String
        switch type {
        case .finals, .seniorPresentation:
            dialogText = "Today is \(label)."
        case .assembly:
            dialogText = "Today is an \(label)."
        default:
            dialogText = "Today is a \(label)."
        }

        return .result(
            dialog: IntentDialog(stringLiteral: dialogText),
            view: InfoSnippetView(title: label, symbolName: "clock", color: type.pillColor, detail: nil)
        )
    }
}
