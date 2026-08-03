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

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard await MainActor.run(body: { settings.accessApproved }) else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)

        let dayKey = DateFormatter.isoDay.string(from: Date())
        guard let (label, pillColor, schedType) = await MainActor.run(body: {
            guard let schedule = store.bellSchedule(for: dayKey) else { return nil as (String, Color, ScheduleType)? }
            let t = schedule.scheduleType
            return (t.scheduleLabel, t.pillColor, t) as (String, Color, ScheduleType)?
        }) else {
            return .result(dialog: "There's no bell schedule loaded for today.")
        }

        let dialogText: String
        switch schedType {
        case .finals, .seniorPresentation:  dialogText = "Today is \(label)."
        case .assembly:                     dialogText = "Today is an \(label)."
        default:                            dialogText = "Today is a \(label)."
        }

        return .result(
            dialog: IntentDialog(stringLiteral: dialogText),
            view: InfoSnippetView(title: label, symbolName: "clock", color: pillColor, detail: nil)
        )
    }
}
