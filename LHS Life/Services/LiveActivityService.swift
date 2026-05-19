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

        let cal      = Calendar.current
        let firstSlot = periods.first(where: { Date() >= $0.startDate && Date() < $0.endDate })
                     ?? periods.first(where: { $0.startDate > Date() })
        let h = firstSlot.map { cal.component(.hour,   from: $0.startDate) } ?? 0
        let m = firstSlot.map { cal.component(.minute, from: $0.startDate) } ?? 0
        let state    = ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m,
            isEnded: false
        )
        let lastBell = periods.last?.endDate ?? Date().addingTimeInterval(3600)

        let attributes = ScheduleActivityAttributes(schoolName: "LaSalle", schedule: periods)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content:    .init(state: state, staleDate: lastBell),
                pushType:   .token
            )
            currentActivity = activity
            print("[LiveActivity] Started — id: \(activity.id), \(periods.count) periods")

            // Observe push token updates and register with Cloudflare Worker
            PushTokenService.observeTokenUpdates(for: activity)

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
            print("[LiveActivity] Foreground update — slot: \(state.slotStartMinutes) min")
        }
    }

    // MARK: - End if school over

    func endIfSchoolOver(state: ScheduleEngine.ScheduleState) {
        switch state.dayState {
        case .afterSchool, .holiday, .pathwaysDay:
            guard currentActivity != nil ||
                  !Activity<ScheduleActivityAttributes>.activities.isEmpty
            else { return }
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
        let cal = Calendar.current

        // Find the active or next upcoming period
        let current = periods.first(where: { now >= $0.startDate && now < $0.endDate })
                   ?? periods.first(where: { $0.startDate > now })

        guard let current else { return nil }

        // slotStartMinutes identifies the slot — worker and widget both use this
        let h = cal.component(.hour,   from: current.startDate)
        let m = cal.component(.minute, from: current.startDate)
        return ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m,
            isEnded: false
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
