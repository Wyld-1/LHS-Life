//
//  NotificationService.swift
//  LHS Life
//
//  Local notifications:
//    1. Professional dress — 9 PM evening before
//    2. ASB — per day mode (announcements only / announcements + store)
//       Skipped on Pathways Days for eligible juniors/seniors
//    3. Abnormal schedule — morning of, for users without Live Activities
//

import Foundation
import UserNotifications

enum NotificationService {

    private static let center = UNUserNotificationCenter.current()

    // MARK: - Category for abnormal schedule action

    static let abnormalScheduleCategoryID = "ABNORMAL_SCHEDULE"
    static let enableLiveActivityActionID = "ENABLE_LIVE_ACTIVITY"

    /// Register notification categories — call once at app launch.
    static func registerCategories() {
        let enableAction = UNNotificationAction(
            identifier: enableLiveActivityActionID,
            title: "Show Today's Schedule",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: abnormalScheduleCategoryID,
            actions: [enableAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Professional Dress

    static func scheduleProfessionalDressNotifications(for events: [SchoolEvent]) async {
        center.removePendingNotificationRequests(withIdentifiers: events.map { "dress-\($0.id)" })
        guard await isAuthorized else { return }
        for event in events.filter({ isProfessionalDressEvent($0) }) {
            await scheduleDressNotification(for: event)
        }
    }

    private static let dressKeywords = [
        "professional dress", "formal dress", "mass attire",
        "dress uniform", "professional attire", "formal attire"
    ]

    static func isProfessionalDressEvent(_ event: SchoolEvent) -> Bool {
        let combined = (event.title + " " + (event.description ?? "")).lowercased()
        return dressKeywords.contains { combined.contains($0) }
    }

    private static func scheduleDressNotification(for event: SchoolEvent) async {
        let calendar = Calendar.current
        guard let evening = calendar.date(byAdding: .day, value: -1, to: event.startDate) else { return }
        var comps = calendar.dateComponents([.year, .month, .day], from: evening)
        comps.hour = 21; comps.minute = 0; comps.second = 0
        guard let fireDate = calendar.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Professional Dress Tomorrow"
        content.body  = "LaSalle requires professional dress for \(event.title)."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "dress-\(event.id)",
                                                     content: content, trigger: trigger))
    }

    // MARK: - ASB Reminders

    static func scheduleASBNotifications(settings: UserSettings, store: CalendarStore) async {
        let existing = await center.pendingNotificationRequests()
        let asbIDs = existing.filter { $0.identifier.hasPrefix("asb-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: asbIDs)

        guard settings.isASBMember, await isAuthorized else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for dayOffset in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: date)
            guard weekday >= 2, weekday <= 6 else { continue }
            let dayIndex = weekday - 2  // 0=Mon…4=Fri
            let mode = settings.asbWorkDays[dayIndex]
            guard mode != .off else { continue }

            let dayKey = DateFormatter.isoDay.string(from: date)
            guard let schedule = store.bellSchedule(for: dayKey) else { continue }

            // Skip Pathways Days for eligible juniors/seniors
            let isPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: store.events, graduationYear: settings.graduationYear
            )
            if isPathways { continue }

            // Announcement always fires for .announcementsOnly and .announcementsAndStore
            await scheduleAnnouncementNotification(date: date, schedule: schedule, dayKey: dayKey)

            // Store notifications only for .announcementsAndStore
            if mode == .announcementsAndStore {
                await scheduleBreakNotification(date: date, schedule: schedule, dayKey: dayKey)
                await scheduleLunchNotification(date: date, schedule: schedule, dayKey: dayKey)
            }
        }
    }

    // MARK: - Shared helper

    /// Returns the first main-school-day period, skipping Period 0 and
    /// any period starting before 7:30 AM. Used by announcement and
    /// abnormal schedule notifications so they fire relative to the
    /// actual school start time, not an optional early period.
    private static func firstMainPeriod(in schedule: BellSchedule) -> Period? {
        // Prefer explicit Period 1
        if let p1 = schedule.periods.first(where: { $0.name == "Period 1" }) { return p1 }
        // Fallback: first period at or after 7:30 AM
        return schedule.periods.first {
            let h = $0.startTime.hour ?? 0
            let m = $0.startTime.minute ?? 0
            return (h == 7 && m >= 30) || h >= 8
        }
    }

    private static func scheduleAnnouncementNotification(date: Date, schedule: BellSchedule, dayKey: String) async {
        guard let firstPeriod = firstMainPeriod(in: schedule),
              let startDate = firstPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -5, to: startDate),
              fireDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Morning Announcements"
        content.body  = "You're doing announcements this morning!"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "asb-announce-\(dayKey)",
                                                     content: content, trigger: trigger))
    }

    private static func scheduleBreakNotification(date: Date, schedule: BellSchedule, dayKey: String) async {
        // Match any period whose name contains "break" — covers "Break",
        // "10 Minute Break", "Morning Break", etc.
        // Only fire for short breaks (≤20 min) — excludes lunch-length slots
        // that might also be named generically.
        guard let breakPeriod = schedule.periods.first(where: {
                  $0.name.lowercased().contains("break") &&
                  ($0.durationMinutes ?? 0) >= 10 &&
                  ($0.durationMinutes ?? 999) <= 20
              }),
              let breakStart = breakPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -5, to: breakStart),
              fireDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Head to Student Store"
        content.body  = "Break starts in 5 minutes."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "asb-break-\(dayKey)",
                                                     content: content, trigger: trigger))
    }

    private static func scheduleLunchNotification(date: Date, schedule: BellSchedule, dayKey: String) async {
        guard let lunchPeriod = schedule.periods.first(where: { $0.name.lowercased() == "lunch" }),
              let lunchStart = lunchPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -5, to: lunchStart),
              fireDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Head to Student Store"
        content.body  = "Lunch starts in 5 minutes."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "asb-lunch-\(dayKey)",
                                                     content: content, trigger: trigger))
    }

    // MARK: - Abnormal Schedule Notifications

    /// Schedules a morning notification for any upcoming day with a non-regular schedule.
    /// Only fires if the user has Live Activities disabled — otherwise they already see it.
    /// Not sent for Pathways Days or holidays — those aren't schedule variations.
    static func scheduleAbnormalScheduleNotifications(settings: UserSettings,
                                                       store: CalendarStore) async {
        // Remove old abnormal notifications
        let existing = await center.pendingNotificationRequests()
        let ids = existing.filter { $0.identifier.hasPrefix("abnormal-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        // Send abnormal notifications only for .off users.
        // .everyDay — already see Dynamic Island, no notification needed.
        // .abnormalOnly — already get Dynamic Island on odd days, no notification needed.
        guard settings.liveActivityMode == .off, await isAuthorized else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let abnormalTypes: Set<ScheduleType> = [.lateStart, .earlyRelease, .assembly, .custom]

        for dayOffset in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let dayKey = DateFormatter.isoDay.string(from: date)
            guard let schedule = store.bellSchedule(for: dayKey) else { continue }
            guard abnormalTypes.contains(schedule.scheduleType) else { continue }

            // Skip Pathways Days — students know they're off campus
            let isPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: store.events, graduationYear: settings.graduationYear
            )
            if isPathways { continue }

            await scheduleAbnormalNotification(date: date, schedule: schedule, dayKey: dayKey)
        }
    }

    private static func scheduleAbnormalNotification(date: Date,
                                                      schedule: BellSchedule,
                                                      dayKey: String) async {
        // Fire 5 minutes before the main school day starts.
        // Uses firstMainPeriod so it adapts to late starts, etc.
        guard let firstPeriod = firstMainPeriod(in: schedule),
              let startDate = firstPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -5, to: startDate),
              fireDate > Date() else { return }

        //let typeName = schedule.scheduleType.rawValue

        let content = UNMutableNotificationContent()
        content.title = "Different Schedule Today"
        content.body  = "Tap to pin the live bell schedule to your home screen."
        content.sound = .default
        content.categoryIdentifier = abnormalScheduleCategoryID

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "abnormal-\(dayKey)",
                                                     content: content, trigger: trigger))
    }
}
