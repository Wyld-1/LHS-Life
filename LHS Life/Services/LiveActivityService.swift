//
//  LiveActivityService.swift
//  LHS Life
//
//  Starting/stopping mechanism copied exactly from LHS Live (working on iOS 26.5).
//  Content builder adapted for LHS Life's Date-based ContentState schema.
//

import Foundation
import ActivityKit

@MainActor
@Observable
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?
    private var lastUpdateTime: Date = .distantPast

    // MARK: - Public API

    func update(state: ScheduleEngine.ScheduleState, settings: UserSettings) {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let scheduleType = SharedStore.readBellSchedules()[dayKey]?.scheduleType

        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else {
            Task { await end() }
            return
        }

        switch state.dayState {
        case .inSession, .betweenPeriods, .beforeSchool:
            if currentActivity == nil {
                start(state: state, settings: settings)
            } else {
                let interval = dynamicUpdateInterval(for: state)
                let now = Date()
                guard now.timeIntervalSince(lastUpdateTime) >= interval else { return }
                lastUpdateTime = now
                let content = buildContentState(from: state, settings: settings)
                let stale = staleDateForNextTransition(state: state)
                Task { await updateContent(content, staleDate: stale) }
            }
        case .afterSchool, .noSchedule, .holiday, .pathwaysDay:
            Task { await end() }
        }
    }

    // MARK: - Dynamic interval

    private func dynamicUpdateInterval(for state: ScheduleEngine.ScheduleState) -> TimeInterval {
        switch state.dayState {
        case .inSession:                     return 300  // 5 min mid-period
        case .betweenPeriods, .beforeSchool: return 30   // 30s at transitions
        default:                             return 300
        }
    }

    private func staleDateForNextTransition(state: ScheduleEngine.ScheduleState) -> Date {
        if let slot = state.currentSlot { return slot.endDate }
        if let next = state.nextSlot    { return next.startDate }
        return Date().addingTimeInterval(300)
    }

    // MARK: - Start

    private func start(state: ScheduleEngine.ScheduleState, settings: UserSettings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let slot     = state.currentSlot ?? state.nextSlot
        let colorHex = slot.flatMap { s in
            s.config.map { ColorPalette.color(at: $0.colorIndex).hex }
        } ?? "#3A6FD8"

        let attributes = ScheduleActivityAttributes(
            periodColorHex: colorHex,
            schoolName: "LaSalle"
        )
        let content = buildContentState(from: state, settings: settings)
        let stale   = staleDateForNextTransition(state: state)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: stale),
                pushType: nil
            )
            currentActivity = activity
            lastUpdateTime  = Date()
            print("[LiveActivity] Started — id: \(activity.id)")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Update

    private func updateContent(_ content: ScheduleActivityAttributes.ContentState,
                                staleDate: Date) async {
        guard let activity = currentActivity else { return }
        await activity.update(.init(state: content, staleDate: staleDate))
    }

    // MARK: - End

    func end() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        lastUpdateTime  = .distantPast
        print("[LiveActivity] Ended")
    }

    // MARK: - Content Builder

    private func buildContentState(
        from state: ScheduleEngine.ScheduleState,
        settings: UserSettings
    ) -> ScheduleActivityAttributes.ContentState {

        let currentName = state.currentSlot?.displayName ?? "—"
        let nextName    = state.nextSlot?.displayName
        let headerText  = ScheduleEngine.headerPrimaryText(for: state)

        let nextBellTime: String?
        if let current = state.currentSlot {
            nextBellTime = ScheduleEngine.timeString(current.endDate)
        } else if let next = state.nextSlot {
            nextBellTime = ScheduleEngine.timeString(next.startDate)
        } else {
            nextBellTime = nil
        }

        let secondsRemaining: Int
        let durationSeconds: Int

        if let slot = state.currentSlot {
            secondsRemaining = max(0, Int(slot.timeRemaining))
            durationSeconds  = max(1, Int(slot.duration))
        } else if let next = state.nextSlot {
            secondsRemaining = max(0, Int(next.startDate.timeIntervalSince(Date())))
            durationSeconds  = max(1, secondsRemaining)
        } else {
            secondsRemaining = 0
            durationSeconds  = 1
        }

        let isOff = state.dayState == .afterSchool
                 || state.dayState == .noSchedule
                 || state.dayState == .holiday
                 || state.dayState == .pathwaysDay

        return ScheduleActivityAttributes.ContentState(
            currentPeriodName:    currentName,
            secondsRemaining:     secondsRemaining,
            periodDurationSeconds: durationSeconds,
            nextPeriodName:       nextName,
            nextBellTime:         nextBellTime,
            isOffSchedule:        isOff,
            headerText:           headerText
        )
    }
}
