//
//  BackgroundTaskService.swift
//  LHS Life
//
//  Registers and handles BGAppRefreshTask so the OS can wake the app
//  at period transitions and push a Live Activity update — even when
//  the app hasn't been opened.
//
//  HOW IT WORKS:
//  1. At every period end (or start), we schedule a BGAppRefreshTask
//     for exactly the next transition moment.
//  2. The OS wakes the app in the background at (approximately) that time.
//  3. The handler rebuilds ScheduleState from SharedStore data — no
//     network call needed, the bell schedule is already on disk.
//  4. It pushes a Live Activity update and schedules the next task.
//
//  IMPORTANT: BGAppRefreshTask gives ~30 seconds of CPU. We stay well
//  under that — no network fetch here, just local date math + ActivityKit.
//
//  REGISTRATION: Call BackgroundTaskService.register() from the App init,
//  before the first scene connects (iOS requirement). Then call
//  scheduleNext(for:) each time the Live Activity is started or updated.
//

import BackgroundTasks
import ActivityKit
import Foundation

enum BackgroundTaskService {

    static let refreshTaskID = "lasalle.schedule.liveActivityRefresh"

    // MARK: - Register handler (call once in App.init)

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskID,
            using: nil
        ) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    // MARK: - Bootstrap (seed the chain without an existing ScheduleState)

    /// Call this at app launch (after schedule data is loaded) and whenever
    /// the Live Activity is expected to run but the BGTask chain may be broken.
    /// Reads today's schedule from SharedStore and schedules an immediate wake
    /// so the OS runs `handle(task:)` as soon as possible.
    static func scheduleBootstrap() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)

        let dayKey = DateFormatter.isoDay.string(from: Date())
        let schedule = SharedStore.readBellSchedules()[dayKey]

        // Find the next meaningful moment: current period end, or next period start.
        // If school hasn't started yet, wake at the first period. If nothing found,
        // wake in 60 seconds as a fallback so we at least try once.
        let wakeDate: Date
        if let schedule = schedule {
            let now = Date()
            let cal = Calendar.current
            let allSlots = schedule.periods.compactMap { period -> (start: Date, end: Date)? in
                guard let s = period.startDate(on: schedule.date, calendar: cal),
                      let e = period.endDate(on: schedule.date, calendar: cal) else { return nil }
                return (s, e)
            }.sorted { $0.start < $1.start }

            // Find the slot we're currently in, or the next one coming up
            if let current = allSlots.first(where: { now >= $0.start && now <= $0.end }) {
                wakeDate = current.end.addingTimeInterval(2)
            } else if let next = allSlots.first(where: { $0.start > now }) {
                wakeDate = next.start.addingTimeInterval(2)
            } else {
                // Past last period — nothing to do today
                return
            }
        } else {
            // No schedule yet; try again in 60 s in case data arrives soon
            wakeDate = Date().addingTimeInterval(60)
        }

        request.earliestBeginDate = wakeDate
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGTask] Bootstrap scheduled for \(wakeDate)")
        } catch {
            print("[BGTask] Bootstrap schedule failed: \(error)")
        }
    }

    // MARK: - Schedule next wake

    /// Schedule a BGAppRefreshTask for the next period transition.
    /// Call this after every Live Activity start or update.
    static func scheduleNext(for state: ScheduleEngine.ScheduleState) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)

        // Wake up at the next transition — when the current slot ends or
        // when the next slot starts. Add a 2-second buffer so the state
        // is cleanly into the new period when we read it.
        if let slot = state.currentSlot {
            request.earliestBeginDate = slot.endDate.addingTimeInterval(2)
        } else if let next = state.nextSlot {
            request.earliestBeginDate = next.startDate.addingTimeInterval(2)
        } else {
            // Nothing left today — no task needed
            return
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler will reject submissions when the device has
            // background app refresh disabled globally — not a crash scenario.
            print("[BGTask] Failed to schedule: \(error)")
        }
    }

    // MARK: - Handle wake

    private static func handle(task: BGAppRefreshTask) {
        // Expire gracefully if the OS cuts us short
        task.expirationHandler = {
            print("[BGTask] Expired before finishing")
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            await performLiveActivityUpdate()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Live Activity update (no network)

    @MainActor
    private static func performLiveActivityUpdate() async {
        let settings = UserSettings.shared
        let bellSchedules = SharedStore.readBellSchedules()
        let events = SharedStore.readEvents()

        let dayKey = DateFormatter.isoDay.string(from: Date())
        let schedule = bellSchedules[dayKey]
        let scheduleType = schedule?.scheduleType

        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else {
            await LiveActivityService.shared.end()
            return
        }

        let isHoliday = events.contains { $0.dayKey == dayKey && $0.category == .holiday }
        let isPathways = PathwaysService.isPathwaysDay(
            on: dayKey, events: events, graduationYear: settings.graduationYear
        )

        let state = ScheduleEngine.state(
            for: Date(),
            schedule: schedule,
            settings: settings,
            isPathwaysDay: isPathways,
            isHoliday: isHoliday
        )

        // Delegate to the service, then schedule the next wake
        LiveActivityService.shared.update(state: state, settings: settings)
        // scheduleNext perpetuates the chain; scheduleBootstrap is a safety net
        // in case update() ends early (e.g. afterSchool) and the chain would die.
        scheduleNext(for: state)
        scheduleBootstrap()
    }
}
