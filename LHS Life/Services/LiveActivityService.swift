//
//  LiveActivityService.swift
//  LHS Life
//
//  Starts, updates, and ends the schedule Live Activity.
//
//  currentActivity is in-memory only — lost on app suspend/resume.
//  reconnect() restores it from ActivityKit's live activities list on launch.
//  updateNow() pushes the correct ContentState immediately — called on foreground
//  so tapping the LA to open the app always fixes stale content.
//

import Foundation
import ActivityKit

@MainActor
@Observable
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?

    // MARK: - Reconnect (call on app launch/foreground)
    // Restores currentActivity from ActivityKit if the app was suspended.

    func reconnect() {
        guard currentActivity == nil else { return }
        currentActivity = Activity<ScheduleActivityAttributes>.activities.first
        if let a = currentActivity {
            print("[LiveActivity] Reconnected to existing activity — id: \(a.id)")
        }
    }

    // MARK: - Start if needed

    func startIfNeeded(schedule: BellSchedule?, settings: UserSettings) {
        // Reconnect first — avoids starting a duplicate if one already exists
        reconnect()
        guard currentActivity == nil else {
            // Already have an activity — just update it
            updateNow(schedule: schedule, settings: settings)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let dayKey       = DateFormatter.isoDay.string(from: Date())
        let scheduleType = schedule?.scheduleType
        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else { return }
        guard let schedule = schedule else { return }

        let periods = buildSchedule(from: schedule, settings: settings)
        guard !periods.isEmpty else { return }

        CachedSchedule.save(periods)

        guard let state = buildContentState(from: periods) else { return }
        let lastBell = periods.last?.endDate ?? Date().addingTimeInterval(3600)

        let attributes = ScheduleActivityAttributes(schoolName: "LaSalle", schedule: periods)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content:    .init(state: state, staleDate: lastBell),
                pushType:   nil
            )
            currentActivity = activity
            print("[LiveActivity] Started — id: \(activity.id), \(periods.count) periods")

            let upcoming = periods.filter { $0.startDate > Date() }
            BellTransitionService.scheduleTransitions(for: upcoming)
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Foreground update
    // Call whenever the app comes to the foreground.
    // Pushes the correct ContentState immediately so stale content is fixed
    // the moment the user taps the Live Activity to open the app.

    func updateNow(schedule: BellSchedule?, settings: UserSettings) {
        reconnect()
        guard let activity = currentActivity else { return }
        guard let schedule = schedule else { return }

        let periods = buildSchedule(from: schedule, settings: settings)
        guard let state = buildContentState(from: periods) else { return }

        Task {
            await activity.update(.init(state: state, staleDate: periods.last?.endDate))
            print("[LiveActivity] Foreground update — now showing: \(state.currentPeriodName)")
        }
    }

    // MARK: - End if school over

    func endIfSchoolOver(state: ScheduleEngine.ScheduleState) {
        switch state.dayState {
        case .afterSchool, .holiday, .pathwaysDay:
            Task { await end() }
        default:
            break
        }
    }

    // MARK: - End

    func end() async {
        CachedSchedule.clear()
        // End all activities in case of duplicates from BGTask timing issues
        for activity in Activity<ScheduleActivityAttributes>.activities {
            await activity.end(.init(state: .init(isEnded: true), staleDate: nil),
                               dismissalPolicy: .immediate)
        }
        currentActivity = nil
        print("[LiveActivity] Ended all activities")
    }

    // MARK: - Content state builder
    // Shared by startIfNeeded and updateNow — always computes from current time.

    func buildContentState(
        from periods: [ScheduleActivityAttributes.ScheduledPeriod]
    ) -> ScheduleActivityAttributes.ContentState? {
        let now = Date()

        let activePeriod = periods.first(where: { now >= $0.startDate && now < $0.endDate })
        let nextPeriod   = periods.first(where: { $0.startDate > now })

        let current: ScheduleActivityAttributes.ScheduledPeriod
        let next:    ScheduleActivityAttributes.ScheduledPeriod?

        if let active = activePeriod {
            let idx = periods.firstIndex(where: { $0.startDate == active.startDate }) ?? 0
            current = active
            next    = idx + 1 < periods.count ? periods[idx + 1] : nil
        } else if let upcoming = nextPeriod {
            // Before school or between periods — synthetic "Soon" slot
            current = ScheduleActivityAttributes.ScheduledPeriod(
                periodNumber:  nil,
                displayName:   "Soon",
                colorHex:      "#94A3B8",
                startDate:     now,
                endDate:       upcoming.startDate,
                endTimeString: upcoming.startDate.formatted(date: .omitted, time: .shortened)
            )
            next = upcoming
        } else {
            return nil  // nothing left today
        }

        return ScheduleActivityAttributes.ContentState(
            currentPeriodName: current.displayName,
            colorHex:          current.colorHex,
            periodStartDate:   current.startDate,
            periodEndDate:     current.endDate,
            nextPeriodName:    next?.displayName,
            nextBellTime:      current.endTimeString,
            isEnded:           false
        )
    }

    // MARK: - Schedule Builder

    func buildSchedule(
        from schedule: BellSchedule,
        settings: UserSettings
    ) -> [ScheduleActivityAttributes.ScheduledPeriod] {
        schedule.periods.compactMap { period -> ScheduleActivityAttributes.ScheduledPeriod? in
            guard let start = period.startDate(on: schedule.date),
                  let end   = period.endDate(on: schedule.date),
                  end > Date()
            else { return nil }

            let num    = extractPeriodNumber(from: period.name)
            let config = num.flatMap { settings.config(for: $0) }
            let colorHex = config.map { ColorPalette.color(at: $0.colorIndex).hex } ?? "#94A3B8"

            return ScheduleActivityAttributes.ScheduledPeriod(
                periodNumber:  num,
                displayName:   config?.displayName ?? period.name,
                colorHex:      colorHex,
                startDate:     start,
                endDate:       end,
                endTimeString: ScheduleEngine.timeString(end)
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func extractPeriodNumber(from name: String) -> Int? {
        let p = name.split(separator: " ")
        guard p.count == 2, p[0].lowercased() == "period" else { return nil }
        return Int(p[1])
    }
}
