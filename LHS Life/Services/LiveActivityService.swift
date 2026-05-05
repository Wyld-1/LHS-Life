//
//  LiveActivityService.swift
//  LHS Life
//
//  Manages the lifecycle of the schedule Live Activity.
//  Starts when school begins, updates every 30 seconds via a timer
//  (ActivityKit throttles updates — 30s is a safe interval),
//  and ends when school is over or the user disables the feature.
//
//  App target only.
//

import Foundation
import ActivityKit
import Combine

@MainActor
final class LiveActivityService: ObservableObject {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?
    private var updateTimer: Timer?

    // MARK: - Public API

    /// Call whenever the schedule state changes or settings are updated.
    func update(state: ScheduleEngine.ScheduleState,
                settings: UserSettings) {
        guard settings.liveActivityEnabled else {
            Task { await end() }
            return
        }

        let content = buildContentState(from: state, settings: settings)

        switch state.dayState {
        case .inSession, .betweenPeriods, .beforeSchool:
            if currentActivity == nil {
                start(state: state, settings: settings)
            } else {
                Task { await updateContent(content) }
            }
        case .afterSchool, .noSchedule, .holiday, .pathwaysDay:
            Task { await end() }
        }
    }

    // MARK: - Start

    private func start(state: ScheduleEngine.ScheduleState, settings: UserSettings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Use the current or next slot's color
        let slot = state.currentSlot ?? state.nextSlot
        let colorHex = slot.flatMap { s in
            s.config.map { ColorPalette.color(at: $0.colorIndex).hex }
        } ?? "#3A6FD8"

        let attributes = ScheduleActivityAttributes(
            periodColorHex: colorHex,
            schoolName: "LaSalle"
        )
        let content = buildContentState(from: state, settings: settings)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: Date().addingTimeInterval(120)),
                pushType: nil
            )
            currentActivity = activity
            startUpdateTimer(settings: settings)
            print("[LiveActivity] Started: \(activity.id)")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Update

    private func updateContent(_ content: ScheduleActivityAttributes.ContentState) async {
        guard let activity = currentActivity else { return }
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(120)))
    }

    // MARK: - End

    func end() async {
        stopUpdateTimer()
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        print("[LiveActivity] Ended")
    }

    // MARK: - Timer (updates every 30s — ActivityKit rate-limits more frequent calls)

    private func startUpdateTimer(settings: UserSettings) {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickUpdate(settings: settings)
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func tickUpdate(settings: UserSettings) {
        // Re-read from SharedStore so widgets stay current without hitting the network
        let schedules  = SharedStore.readBellSchedules()
        let dayKey     = DateFormatter.isoDay.string(from: Date())
        let schedule   = schedules[dayKey]
        let state      = ScheduleEngine.state(
            for: Date(),
            schedule: schedule,
            settings: settings,
            isPathwaysDay: false,
            isHoliday: false
        )
        update(state: state, settings: settings)
    }

    // MARK: - Content Builder

    private func buildContentState(
        from state: ScheduleEngine.ScheduleState,
        settings: UserSettings
    ) -> ScheduleActivityAttributes.ContentState {

        let currentName   = state.currentSlot?.displayName ?? "—"
        let nextName      = state.nextSlot?.displayName
        let headerText    = ScheduleEngine.headerPrimaryText(for: state)

        let secondsRemaining: Int
        let durationSeconds: Int

        if let slot = state.currentSlot {
            secondsRemaining = max(0, Int(slot.timeRemaining))
            durationSeconds  = max(1, Int(slot.duration))
        } else if let next = state.nextSlot {
            // Between periods — count down to next period start
            secondsRemaining = max(0, Int(next.startDate.timeIntervalSince(Date())))
            durationSeconds  = secondsRemaining  // progress stays at 0
        } else {
            secondsRemaining = 0
            durationSeconds  = 1
        }

        let isOff = state.dayState == .afterSchool
                 || state.dayState == .noSchedule
                 || state.dayState == .holiday
                 || state.dayState == .pathwaysDay

        return ScheduleActivityAttributes.ContentState(
            currentPeriodName: currentName,
            secondsRemaining: secondsRemaining,
            periodDurationSeconds: durationSeconds,
            nextPeriodName: nextName,
            isOffSchedule: isOff,
            headerText: headerText
        )
    }
}
