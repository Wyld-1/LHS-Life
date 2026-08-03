//
//  NextClassIntent.swift
//  LHS Life
//
//  "What's my next class in LHS Life" — answers WHICH class, not how much
//  time is left (that's NextBellIntent). Reuses ScheduleEngine.state(),
//  the same pure function the header/widget/Live Activity all already use.
//
//  Reads CalendarStore.shared directly rather than via @Dependency —
//  @Dependency/AppDependencyManager proved unreliable specifically for
//  intents that don't set openAppWhenRun (background-launched by Siri),
//  a known, repeatedly-reported gap in Apple's own developer forums.
//  A static singleton has no registration-timing race at all.
//

import AppIntents
import SwiftUI

struct NextClassIntent: AppIntent {
    static let title: LocalizedStringResource = "What's My Next Class"
    static let description = IntentDescription(
        "Tells you what class is next, or what class you're currently in."
    )

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard await MainActor.run(body: { settings.accessApproved }) else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)

        // Collect all MainActor-isolated data in one hop
        let (state, nextSlotStartStr, currentSlotStr, nextAfterStr, progressVal) = await MainActor.run {
            let s = store.todayState()
            let currentName  = s.currentSlot?.displayName ?? ""
            let currentMins  = s.currentSlot.map { NextClassIntent.minutesRemainingText($0) } ?? ""
            let currentProg  = s.currentSlot?.progress
            let nextName     = s.nextSlot?.displayName ?? ""
            let nextStart    = s.nextSlot.map { ScheduleEngine.timeString($0.startDate) } ?? ""
            let nextEnd      = s.nextSlot.map { ScheduleEngine.timeString($0.endDate) } ?? ""
            let currentColor = s.currentSlot?.config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
            let nextColor    = s.nextSlot?.config.map    { Color.paletteColor(for: $0) } ?? Color.lsTertiary
            return (s, nextStart, currentName, nextEnd, (currentProg, currentColor, currentMins, nextName, nextStart, nextColor))
        }
        let (currentProgress, currentColor, currentMinsText, nextName, nextStartText, nextColor) = progressVal

        switch state.dayState {
        case .inSession:
            guard state.currentSlot != nil else {
                return .result(dialog: "There's no class right now.")
            }
            let view = ClassStatusSnippetView(
                className: currentSlotStr,
                color: currentColor,
                progress: currentProgress,
                statusText: currentMinsText
            )
            if state.nextSlot != nil {
                let dialog: IntentDialog = "You're in \(currentSlotStr) now. Next up: \(nextName) at \(nextStartText)."
                return .result(dialog: dialog, view: view)
            } else {
                let dialog: IntentDialog = "You're in \(currentSlotStr) — your last class today."
                return .result(dialog: dialog, view: view)
            }

        case .betweenPeriods:
            guard state.nextSlot != nil else {
                return .result(dialog: "No more classes today.")
            }
            let dialog: IntentDialog = "Your next class is \(nextName) at \(nextStartText)."
            let view = ClassStatusSnippetView(
                className: nextName,
                color: nextColor,
                progress: nil,
                statusText: "Starts at \(nextStartText)"
            )
            return .result(dialog: dialog, view: view)

        case .beforeSchool:
            guard state.nextSlot != nil else {
                return .result(dialog: "There's no school today.")
            }
            let dialog: IntentDialog = "School starts at \(nextStartText) with \(nextName)."
            let view = ClassStatusSnippetView(
                className: nextName,
                color: nextColor,
                progress: nil,
                statusText: "Starts at \(nextStartText)"
            )
            return .result(dialog: dialog, view: view)

        case .afterSchool:  return .result(dialog: "School's out for the day.")
        case .noSchedule:   return .result(dialog: "There's no school today.")
        case .pathwaysDay:  return .result(dialog: "It's a Pathways day — no on-campus classes.")
        case .holiday:      return .result(dialog: "There's no school today.")
        }
    }

    // MARK: - Shared helpers (also used by NextBellIntent)

    static func minutesRemainingText(_ slot: ScheduleEngine.ActiveSlot) -> String {
        "\(Int(ceil(slot.timeRemaining / 60))) min left"
    }

    static func snippet(
        for slot: ScheduleEngine.ActiveSlot,
        statusText: String,
        progress: Double? = nil
    ) -> ClassStatusSnippetView {
        let color = slot.config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
        return ClassStatusSnippetView(
            className: slot.displayName,
            color: color,
            progress: progress,
            statusText: statusText
        )
    }
}
