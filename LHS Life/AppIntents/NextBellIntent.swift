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

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard await MainActor.run(body: { settings.accessApproved }) else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)

        let (state, dialogText, currentName, currentMins, currentProg, currentColor, nextName, nextStart, nextColor) = await MainActor.run {
            let s        = store.todayState()
            let primary  = ScheduleEngine.headerPrimaryText(for: s)
            let curName  = s.currentSlot?.displayName ?? ""
            let curMins  = s.currentSlot.map { NextClassIntent.minutesRemainingText($0) } ?? ""
            let curProg  = s.currentSlot?.progress
            let curColor = s.currentSlot?.config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
            let nxtName  = s.nextSlot?.displayName ?? ""
            let nxtStart = s.nextSlot.map { ScheduleEngine.timeString($0.startDate) } ?? ""
            let nxtColor = s.nextSlot?.config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
            return (s, primary, curName, curMins, curProg, curColor, nxtName, nxtStart, nxtColor)
        }
        let dialog: IntentDialog = "\(dialogText)"

        switch state.dayState {
        case .inSession:
            guard state.currentSlot != nil else { return .result(dialog: dialog) }
            return .result(dialog: dialog, view: ClassStatusSnippetView(
                className: currentName, color: currentColor,
                progress: currentProg, statusText: currentMins
            ))
        case .betweenPeriods, .beforeSchool:
            guard state.nextSlot != nil else { return .result(dialog: dialog) }
            return .result(dialog: dialog, view: ClassStatusSnippetView(
                className: nextName, color: nextColor,
                progress: nil, statusText: "Starts at \(nextStart)"
            ))
        case .afterSchool, .noSchedule, .pathwaysDay, .holiday:
            return .result(dialog: dialog)
        }
    }
}
