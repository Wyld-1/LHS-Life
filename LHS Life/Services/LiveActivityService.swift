//
//  LiveActivityService.swift
//  LHS Life
//
//  Starts and ends the schedule Live Activity.
//  All content updates are server-pushed via the Cloudflare Worker.
//
//  currentActivity is in-memory only — lost on app suspend/resume.
//  reconnect() restores it from ActivityKit's live activities list on launch.
//

import Foundation
import ActivityKit
import UserNotifications

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
        reconnect()
        guard currentActivity == nil else {
            print("[LiveActivity] startIfNeeded bailed — activity already running (id: \(currentActivity!.id))")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] startIfNeeded bailed — activities not enabled")
            return
        }
        let scheduleType = schedule?.scheduleType
        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else {
            print("[LiveActivity] startIfNeeded bailed — liveActivityEffectivelyEnabled returned false (type: \(String(describing: scheduleType)))")
            return
        }
        guard let schedule = schedule else {
            print("[LiveActivity] startIfNeeded bailed — schedule is nil")
            return
        }
        let periods = buildSchedule(from: schedule, settings: settings)
        guard !periods.isEmpty else {
            print("[LiveActivity] startIfNeeded bailed — periods empty after buildSchedule")
            return
        }
        if let firstBell = periods.first?.startDate, firstBell.timeIntervalSinceNow > 3600 {
            print("[LiveActivity] startIfNeeded bailed — first bell too far away (\(Int(firstBell.timeIntervalSinceNow / 60))min)")
            return
        }

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

        let attributes = ScheduleActivityAttributes(
            schoolName: "LaSalle",
            scheduleTypeName: schedule.scheduleType.scheduleLabel,
            schedule: periods
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content:    .init(state: state, staleDate: lastBell),
                pushType:   .token
            )
            currentActivity = activity
            print("[LiveActivity] Started — id: \(activity.id), \(periods.count) periods")

            // Cancel the "school starts soon" reminder — LA is already running
            let todayKey = DateFormatter.isoDay.string(from: Date())
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["lareminder-\(todayKey)"]
            )

            // Register the initial push token immediately (it's already available
            // on activity.pushToken at this point), then watch for rotations.
            // Relying solely on pushTokenUpdates risks missing the first token
            // if the stream doesn't emit before the app backgrounds.
            if let initialToken = activity.pushToken {
                Task { await PushTokenService.register(token: initialToken, periods: periods) }
            }
            PushTokenService.observeTokenUpdates(for: activity, periods: periods)

            let upcoming = periods.filter { $0.startDate > Date() }
            BellTransitionService.scheduleTransitions(for: upcoming)
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
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
        let mapped = schedule.periods.compactMap { period -> ScheduleActivityAttributes.ScheduledPeriod? in
            guard let start = period.startDate(on: schedule.date),
                  let end   = period.endDate(on: schedule.date),
                  end > Date()
            else { return nil }

            // Handle "Period 5 Final" — extract the number from the base name,
            // then re-attach " Final" to the user's configured class display name.
            let hasFinalSuffix = period.name.hasSuffix(" Final")
            let baseName = hasFinalSuffix
                ? String(period.name.dropLast(" Final".count))
                : period.name

            let num    = extractPeriodNumber(from: baseName)
            let config = num.flatMap { settings.config(for: $0) }

            // Skip periods the user has disabled.
            // Named slots without a period number (Senior Presentation, Break, Lunch)
            // are never disabled — they have no config.
            if let config, !config.isEnabled { return nil }

            let colorHex    = config.map { ColorPalette.color(at: $0.colorIndex).hex } ?? "#94A3B8"
            let baseDisplay = config?.displayName ?? baseName
            let displayName = hasFinalSuffix ? "\(baseDisplay) Final" : baseDisplay

            return ScheduleActivityAttributes.ScheduledPeriod(
                periodNumber:  num,
                displayName:   displayName,
                colorHex:      colorHex,
                startDate:     start,
                endDate:       end,
                endTimeString: ScheduleEngine.timeString(end)
            )
        }
        .sorted { $0.startDate < $1.startDate }

        // Synthesize passing periods for implicit gaps between consecutive periods.
        // The schedule data has no explicit Passing entries — the gaps are implicit.
        // Without this, the worker never fires during passing and the widget holds
        // the previous period until the next class starts.
        var withPassing: [ScheduleActivityAttributes.ScheduledPeriod] = []
        for (i, period) in mapped.enumerated() {
            withPassing.append(period)
            guard i < mapped.count - 1 else { continue }
            let next = mapped[i + 1]
            let gap = next.startDate.timeIntervalSince(period.endDate)
            // ≤ 10 min = passing period. Longer gaps are already named (Break, Lunch).
            if gap > 0 && gap <= 600 {
                withPassing.append(ScheduleActivityAttributes.ScheduledPeriod(
                    periodNumber: nil,
                    displayName: "Passing",
                    colorHex: "#94A3B8",
                    startDate: period.endDate,
                    endDate: next.startDate,
                    endTimeString: ScheduleEngine.timeString(next.startDate)
                ))
            }
        }
        return withPassing
    }

    private func extractPeriodNumber(from name: String) -> Int? {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, parts[0].lowercased() == "period" else { return nil }
        return Int(parts[1])
    }
}
