//
//  BellTransitionService.swift
//  LHS Life
//
//  Schedules one BGProcessingTask per period transition for today.
//  Each task fires exactly at the bell, wakes the app for ~30 seconds,
//  pushes the new ContentState to the Live Activity, and exits.
//
//  Task identifier: lasalle.bell.transition
//  Must be registered in BGTaskSchedulerPermittedIdentifiers in Info.plist.
//

import Foundation
import BackgroundTasks
import ActivityKit

enum BellTransitionService {

    static let taskIdentifier = "lasalle.bell.transition"

    // MARK: - Registration
    // Call once at app launch, before the first scene connects.

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            handleTask(task)
        }
    }

    // MARK: - Schedule all transitions for today
    // Call after the live activity starts. Cancels any previously scheduled
    // tasks first, then schedules one per upcoming period transition.

    static func scheduleTransitions(for periods: [ScheduleActivityAttributes.ScheduledPeriod]) {
        // Cancel any stale tasks from a previous session
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        let upcoming = periods.filter { $0.startDate > Date() }
        guard !upcoming.isEmpty else {
            print("[BellTransition] No upcoming transitions to schedule")
            return
        }

        // Schedule the first upcoming transition — each task re-schedules the next
        scheduleNext(in: upcoming)
        print("[BellTransition] Scheduled \(upcoming.count) transition(s)")
    }

    // MARK: - Internal

    private static func scheduleNext(in remaining: [ScheduleActivityAttributes.ScheduledPeriod]) {
        guard let next = remaining.first else { return }

        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = next.startDate
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BellTransition] Scheduled task for \(next.displayName) at \(next.startDate)")
        } catch {
            print("[BellTransition] Failed to schedule: \(error)")
        }
    }

    // MARK: - Task handler

    private static func handleTask(_ task: BGProcessingTask) {
        print("[BellTransition] Task fired")

        task.expirationHandler = {
            print("[BellTransition] Task expired before completion")
            task.setTaskCompleted(success: false)
        }

        // Load cached schedule from App Group
        guard let periods = CachedSchedule.load() else {
            print("[BellTransition] No cached schedule — cannot update")
            task.setTaskCompleted(success: false)
            return
        }

        let now = Date()

        // Find the period that just started (within last 2 minutes)
        guard periods.first(where: {
            now >= $0.startDate && now.timeIntervalSince($0.startDate) < 120
        }) != nil else {
            print("[BellTransition] No transition found at \(now)")
            // Still schedule the next one
            let remaining = periods.filter { $0.startDate > now }
            scheduleNext(in: remaining)
            task.setTaskCompleted(success: true)
            return
        }

        let contentState = LiveActivityService.shared.buildContentState(from: periods)

        guard let contentState = contentState else {
            print("[BellTransition] Could not build content state")
            let remaining = periods.filter { $0.startDate > now }
            scheduleNext(in: remaining)
            task.setTaskCompleted(success: false)
            return
        }

        // Push to live activity
        Task {
            await pushToActivity(contentState: contentState)

            // Schedule the next transition
            let remaining = periods.filter { $0.startDate > now }
            scheduleNext(in: remaining)

            task.setTaskCompleted(success: true)
            print("[BellTransition] Updated activity — \(contentState.currentPeriodName), next: \(contentState.nextPeriodName ?? "none")")
        }
    }

    private static func pushToActivity(
        contentState: ScheduleActivityAttributes.ContentState
    ) async {
        let activities = Activity<ScheduleActivityAttributes>.activities
        guard let activity = activities.first else {
            print("[BellTransition] No active Live Activity to update")
            return
        }

        let content = ActivityContent(
            state: contentState,
            staleDate: contentState.periodEndDate
        )

        await activity.update(content)
        print("[BellTransition] Activity updated successfully")
    }
}

// MARK: - Cached Schedule
// Persists the day's schedule to App Group UserDefaults so BGProcessingTask
// can read it without needing CalendarStore to be loaded.

enum CachedSchedule {
    private static let key      = "cached_bell_schedule"
    private static let defaults = UserDefaults(suiteName: "group.lasalle.widgetinfo")

    static func save(_ periods: [ScheduleActivityAttributes.ScheduledPeriod]) {
        guard let data = try? JSONEncoder().encode(periods) else { return }
        defaults?.set(data, forKey: key)
        print("[CachedSchedule] Saved \(periods.count) periods")
    }

    static func load() -> [ScheduleActivityAttributes.ScheduledPeriod]? {
        guard let data = defaults?.data(forKey: key),
              let periods = try? JSONDecoder().decode(
                  [ScheduleActivityAttributes.ScheduledPeriod].self,
                  from: data
              )
        else { return nil }
        return periods
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
