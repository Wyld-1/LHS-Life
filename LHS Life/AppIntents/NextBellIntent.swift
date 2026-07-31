//
//  NextBellIntent.swift
//  LHS Life
//
//  "When's the next bell" / "how much time is left in class" — answers the
//  TIME question, not which class (that's NextClassIntent). Dialog text is
//  ScheduleEngine.headerPrimaryText verbatim — the same string your header
//  already speaks — so Siri's answer can never drift from the in-app one.
//
//  Reads CalendarStore.shared directly — see NextClassIntent.swift header
//  comment for why this replaced @Dependency.
//

import AppIntents
import SwiftUI

struct NextBellIntent: AppIntent {
    static let title: LocalizedStringResource = "When's the Next Bell"
    static let description = IntentDescription(
        "Tells you how much time is left in your current class, or when the next one starts."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = CalendarStore.shared
        let settings = UserSettings.shared
        guard settings.accessApproved else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        let state = store.todayState()
        let dialog: IntentDialog = "\(ScheduleEngine.headerPrimaryText(for: state))"

        switch state.dayState {
        case .inSession:
            guard let current = state.currentSlot else { return .result(dialog: dialog) }
            return .result(dialog: dialog, view: NextClassIntent.snippet(
                for: current,
                statusText: NextClassIntent.minutesRemainingText(current),
                progress: current.progress
            ))
        case .betweenPeriods, .beforeSchool:
            guard let next = state.nextSlot else { return .result(dialog: dialog) }
            return .result(dialog: dialog, view: NextClassIntent.snippet(
                for: next,
                statusText: "Starts at \(ScheduleEngine.timeString(next.startDate))"
            ))
        case .afterSchool, .noSchedule, .pathwaysDay, .holiday:
            return .result(dialog: dialog)
        }
    }
}
