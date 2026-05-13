//
//  LiveActivityService.swift
//  LHS Life
//
//  Starts, maintains, and ends the schedule Live Activity.
//
//  The entire day's schedule is written into the static ActivityAttributes
//  at start time. The widget computes what to display using context.date
//  and a TimelineView — no updates are ever pushed after start.
//
//  The app calls update() from the pill timer only to check whether
//  the school day has ended and the activity should be dismissed.
//

import Foundation
import ActivityKit

@MainActor
@Observable
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?

    // MARK: - Public API

    /// Call once after schedule data loads. Starts the activity for the full day.
    func startIfNeeded(schedule: BellSchedule?, settings: UserSettings) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard currentActivity == nil else { return }

        let dayKey = DateFormatter.isoDay.string(from: Date())
        let scheduleType = schedule?.scheduleType
        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else { return }

        guard let schedule = schedule else { return }

        // Build the full day schedule — all periods with resolved colors
        let scheduledPeriods = buildSchedule(from: schedule, settings: settings)
        guard !scheduledPeriods.isEmpty else { return }

        // Last bell is the stale date — activity dims naturally after school ends
        let lastBell = scheduledPeriods.last?.endDate ?? Date().addingTimeInterval(3600)

        let attributes = ScheduleActivityAttributes(
            schoolName: "LaSalle",
            schedule: scheduledPeriods
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: .init(), staleDate: lastBell),
                pushType: nil
            )
            currentActivity = activity
            print("[LiveActivity] Started — id: \(activity.id), \(scheduledPeriods.count) periods")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Called from the pill timer. Only used to end the activity after school.
    func endIfSchoolOver(state: ScheduleEngine.ScheduleState) {
        switch state.dayState {
        case .afterSchool, .holiday, .pathwaysDay:
            Task { await end() }
        default:
            break
        }
    }

    /// End the activity immediately.
    func end() async {
        guard let activity = currentActivity else { return }
        await activity.end(
            .init(state: .init(isEnded: true), staleDate: nil),
            dismissalPolicy: .immediate
        )
        currentActivity = nil
        print("[LiveActivity] Ended")
    }

    // MARK: - Schedule Builder

    private func buildSchedule(
        from schedule: BellSchedule,
        settings: UserSettings
    ) -> [ScheduleActivityAttributes.ScheduledPeriod] {

        schedule.periods.compactMap { period -> ScheduleActivityAttributes.ScheduledPeriod? in
            guard let start = period.startDate(on: schedule.date),
                  let end   = period.endDate(on: schedule.date),
                  end > Date()  // skip periods already over
            else { return nil }

            let periodNumber = extractPeriodNumber(from: period.name)
            let config       = periodNumber.flatMap { settings.config(for: $0) }

            let colorHex: String
            if let config = config {
                colorHex = ColorPalette.color(at: config.colorIndex).hex
            } else {
                colorHex = "#94A3B8"  // slate gray for breaks, lunch, advisory
            }

            return ScheduleActivityAttributes.ScheduledPeriod(
                periodNumber:  periodNumber,
                fallbackName:  period.name,
                colorHex:      colorHex,
                startDate:     start,
                endDate:       end,
                endTimeString: ScheduleEngine.timeString(end)
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func extractPeriodNumber(from name: String) -> Int? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "period" else { return nil }
        return Int(parts[1])
    }
}
