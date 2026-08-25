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
import OSLog

@MainActor
@Observable
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?
    private(set) var isDebugSession = false

    // MARK: - Reconnect (call on app launch/foreground)
    // Restores currentActivity from ActivityKit if the app was suspended.

    /// True when a Live Activity is currently running.
    var isRunning: Bool { currentActivity != nil }

    /// Set when the user taps the "Start Live Activities" notification
    /// action. Consumed on the next foreground so the confirmation overlay
    /// appears once the app is actually on screen — the action itself may
    /// fire while the app is backgrounded, where an overlay would be lost.
    var pendingStartConfirmation = false

    /// Why the last startIfNeeded call declined to start, phrased for the
    /// user rather than the log. nil after a successful start (or when one
    /// was already running).
    ///
    /// Separate from the LHSLogger lines on purpose: those name internal
    /// state ("liveActivityEffectivelyEnabled false (mode: .off…)") and are
    /// for us. These are for a sophomore reading a card on their phone.
    private(set) var lastStartFailure: String?

    func reconnect() {
        guard currentActivity == nil else { return }
        currentActivity = Activity<ScheduleActivityAttributes>.activities.first
        if let a = currentActivity {
            LHSLogger.liveActivity.notice("Reconnected to existing activity — id: \(a.id, privacy: .public)")
        }
    }

    // MARK: - Start if needed

    func startIfNeeded(schedule: BellSchedule?, settings: UserSettings) {
        reconnect()
        guard currentActivity == nil else {
            LHSLogger.liveActivity.notice("bail: activity already running (id: \(self.currentActivity!.id, privacy: .public))")
            // Already running is a success from the user's point of view —
            // they asked for a Live Activity and there is one.
            lastStartFailure = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LHSLogger.liveActivity.error("bail: activities not enabled in system settings")
            lastStartFailure = "Turn on Live Activities in iPhone Settings"
            return
        }
        let scheduleType = schedule?.scheduleType
        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else {
            LHSLogger.liveActivity.error(
                "bail: liveActivityEffectivelyEnabled false (mode: \(String(describing: settings.liveActivityMode), privacy: .public), type: \(String(describing: scheduleType), privacy: .public))"
            )
            lastStartFailure = "Live Activities are turned off in LHS Life settings"
            return
        }
        guard let schedule = schedule else {
            LHSLogger.liveActivity.error("bail: schedule is nil")
            lastStartFailure = "No bell schedule for today"
            return
        }
        let periods = buildSchedule(from: schedule, settings: settings)
        guard !periods.isEmpty else {
            LHSLogger.liveActivity.error("bail: periods empty after buildSchedule")
            lastStartFailure = "No classes enabled in your schedule"
            return
        }
        if let firstBell = periods.first?.startDate, firstBell.timeIntervalSinceNow > 3600 {
            LHSLogger.liveActivity.notice("bail: first bell too far away (\(Int(firstBell.timeIntervalSinceNow / 60))min)")
            lastStartFailure = "School hasn't started yet today"
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
            lastStartFailure = nil
            LHSLogger.liveActivity.notice("Started — id: \(activity.id, privacy: .public), \(periods.count) periods")

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
            // The likeliest TestFlight-only failure: pushType: .token requires
            // the push entitlement, and an App Store provisioning profile
            // generated before Push Notifications was enabled on the App ID
            // won't carry it. Logged at .error so it survives to Console.app.
            LHSLogger.liveActivity.error("Failed to start: \(String(describing: error), privacy: .public)")
            lastStartFailure = "Couldn't start Live Activities"
        }
    }

    // MARK: - Dummy start (debug only)
    // Starts a fake 2-minute schedule anchored to now, immune to school-over checks.

    func startDummy() {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let p1End   = now.addingTimeInterval(120)
        let passEnd = now.addingTimeInterval(150)
        let p2End   = now.addingTimeInterval(270)
        let periods: [ScheduleActivityAttributes.ScheduledPeriod] = [
            .init(periodNumber: 1,   displayName: "English",
                  colorHex: "#FF6B6B",
                  startDate: now.addingTimeInterval(-5), endDate: p1End,
                  endTimeString: fmt.string(from: p1End)),
            .init(periodNumber: nil, displayName: "Passing",
                  colorHex: "#94A3B8",
                  startDate: p1End, endDate: passEnd,
                  endTimeString: fmt.string(from: passEnd)),
            .init(periodNumber: 2,   displayName: "Chemistry",
                  colorHex: "#F5B800",
                  startDate: passEnd, endDate: p2End,
                  endTimeString: fmt.string(from: p2End)),
        ]
        let cal = Calendar.current
        let h   = cal.component(.hour,   from: periods[0].startDate)
        let m   = cal.component(.minute, from: periods[0].startDate)
        let state = ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m, isEnded: false
        )
        CachedSchedule.save(periods)
        do {
            let activity = try Activity.request(
                attributes: ScheduleActivityAttributes(
                    schoolName: "LaSalle",
                    scheduleTypeName: "Debug Schedule",
                    schedule: periods
                ),
                content: .init(state: state, staleDate: now.addingTimeInterval(6000)),
                pushType: .token
            )
            currentActivity = activity
            isDebugSession  = true
            print("[LiveActivity] Dummy started — id: \(activity.id)")
            if let initialToken = activity.pushToken {
                Task { await PushTokenService.register(token: initialToken, periods: periods) }
            }
            PushTokenService.observeTokenUpdates(for: activity, periods: periods)
            BellTransitionService.scheduleTransitions(for: periods.filter { $0.startDate > now })
        } catch {
            print("[LiveActivity] Dummy start failed: \(error)")
        }
    }

    // MARK: - End if school over

    func endIfSchoolOver(state: ScheduleEngine.ScheduleState) {
        guard !isDebugSession else { return }   // leave debug sessions alone
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
        isDebugSession = false
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
