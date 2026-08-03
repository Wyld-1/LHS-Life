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

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard await MainActor.run(body: { settings.accessApproved }) else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)

        let now = Date()
        let (next) = await MainActor.run {
            store.events
                .filter { $0.isProfessionalDress && $0.startDate > now }
                .sorted { $0.startDate < $1.startDate }
                .first
        }

        guard let next else {
            return .result(dialog: "I don't see an upcoming professional dress day yet.")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        let dateStr = formatter.string(from: next.startDate)

        return .result(
            dialog: "The next professional dress day is \(dateStr).",
            view: InfoSnippetView(
                title: "Professional Dress Day",
                symbolName: "tshirt.fill",
                color: Color.lsOrange,
                detail: dateStr
            )
        )
    }
}
