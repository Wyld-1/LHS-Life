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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = CalendarStore.shared
        let settings = UserSettings.shared
        guard settings.accessApproved else {
            return .result(dialog: AppIntentSupport.setupIncompleteDialog)
        }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        let state = store.todayState()

        switch state.dayState {
        case .inSession:
            guard let current = state.currentSlot else {
                return .result(dialog: "There's no class right now.")
            }
            let view = Self.snippet(for: current, statusText: Self.minutesRemainingText(current), progress: current.progress)
            if let next = state.nextSlot {
                let dialog: IntentDialog = "You're in \(current.displayName) now. Next up: \(next.displayName) at \(ScheduleEngine.timeString(next.startDate))."
                return .result(dialog: dialog, view: view)
            } else {
                let dialog: IntentDialog = "You're in \(current.displayName) — your last class today."
                return .result(dialog: dialog, view: view)
            }

        case .betweenPeriods:
            guard let next = state.nextSlot else {
                return .result(dialog: "No more classes today.")
            }
            let dialog: IntentDialog = "Your next class is \(next.displayName) at \(ScheduleEngine.timeString(next.startDate))."
            let view = Self.snippet(for: next, statusText: "Starts at \(ScheduleEngine.timeString(next.startDate))", progress: nil)
            return .result(dialog: dialog, view: view)

        case .beforeSchool:
            guard let next = state.nextSlot else {
                return .result(dialog: "There's no school today.")
            }
            let dialog: IntentDialog = "School starts at \(ScheduleEngine.timeString(next.startDate)) with \(next.displayName)."
            let view = Self.snippet(for: next, statusText: "Starts at \(ScheduleEngine.timeString(next.startDate))", progress: nil)
            return .result(dialog: dialog, view: view)

        case .afterSchool:
            return .result(dialog: "School's out for the day.")
        case .noSchedule:
            return .result(dialog: "There's no school today.")
        case .pathwaysDay:
            return .result(dialog: "It's a Pathways day — no on-campus classes.")
        case .holiday:
            return .result(dialog: "There's no school today.")
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
