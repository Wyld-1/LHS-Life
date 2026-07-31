//
//  NextProfessionalDressDayIntent.swift
//  LHS Life
//
//  "When's the next professional dress day" — first upcoming event tagged
//  .professionalDress by BellScheduleDetector, same category the calendar
//  UI already relies on.
//
//  Reads CalendarStore.shared directly — see NextClassIntent.swift header
//  comment for why this replaced @Dependency.
//

import AppIntents
import SwiftUI

struct NextProfessionalDressDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Professional Dress Day"
    static let description = IntentDescription("Tells you when the next professional dress day is.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = CalendarStore.shared
        let settings = UserSettings.shared
        guard settings.accessApproved else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        let now = Date()
        let upcoming = store.events
            .filter { $0.isProfessionalDress && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        guard let next = upcoming.first else {
            return .result(dialog: "I don't see an upcoming professional dress day yet.")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        let dateStr = formatter.string(from: next.startDate)

        let dialog: IntentDialog = "The next professional dress day is \(dateStr)."
        let view = InfoSnippetView(
            title: "Professional Dress Day",
            symbolName: "tshirt.fill",
            color: Color.lsOrange,
            detail: dateStr
        )
        return .result(dialog: dialog, view: view)
    }
}
