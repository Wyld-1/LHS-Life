//
//  NotificationService.swift
//  LHS Life
//
//  Schedules two kinds of local notifications:
//    1. Professional dress — 9 PM the evening before
//    2. ASB reminders — on work days:
//       • 10 min before school starts: announcement reminder + TeamReach deep link
//       • 5 min before break ends: head to Student Store
//       • 5 min before lunch ends: head to Student Store
//

import Foundation
import UserNotifications

enum NotificationService {

    private static let center = UNUserNotificationCenter.current()

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[NotificationService] Auth failed: \(error)")
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
        content.body  = "LaSalle requires professional dress for \(event.title) tomorrow."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "dress-\(event.id)",
                                                     content: content, trigger: trigger))
    }

    // MARK: - ASB Reminders

    /// Call whenever ASB settings or the bell schedule changes.
    /// Replaces all existing ASB notifications with fresh ones for the next 14 days.
    static func scheduleASBNotifications(settings: UserSettings,
                                          store: CalendarStore) async {
        // Clear all existing ASB notifications
        let existing = await center.pendingNotificationRequests()
        let asbIDs = existing.filter { $0.identifier.hasPrefix("asb-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: asbIDs)

        guard settings.isASBMember, await isAuthorized else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Schedule for the next 14 days
        for dayOffset in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: date)  // 1=Sun…7=Sat
            guard weekday >= 2, weekday <= 6 else { continue }  // Mon–Fri only
            let dayIndex = weekday - 2  // 0=Mon…4=Fri
            guard settings.asbWorkDays[dayIndex] else { continue }

            let dayKey = DateFormatter.isoDay.string(from: date)
            guard let schedule = store.bellSchedule(for: dayKey) else { continue }

            await scheduleAnnouncementNotification(date: date, schedule: schedule, dayKey: dayKey)
            await scheduleBreakNotification(date: date, schedule: schedule, dayKey: dayKey)
            await scheduleLunchNotification(date: date, schedule: schedule, dayKey: dayKey)
        }
    }

    // 10 min before school starts — announcement reminder with TeamReach link
    private static func scheduleAnnouncementNotification(date: Date, schedule: BellSchedule, dayKey: String) async {
        guard let firstPeriod = schedule.periods.first,
              let startDate = firstPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -10, to: startDate),
              fireDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Announcement Time"
        content.body  = "School starts in 10 minutes. Time to do announcements!"
        content.sound = .default
        // Deep link to open TeamReach app (standard URL scheme)
        content.userInfo = ["url": "teamreach://"]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "asb-announce-\(dayKey)",
                                                     content: content, trigger: trigger))
    }

    // 5 min before break STARTS — head to Student Store
    private static func scheduleBreakNotification(date: Date, schedule: BellSchedule, dayKey: String) async {
        guard let breakPeriod = schedule.periods.first(where: { $0.name.lowercased() == "break" }),
              let breakStart = breakPeriod.startDate(on: date),
              let fireDate = Calendar.current.date(byAdding: .minute, value: -5, to: breakStart),
              fireDate > Date()
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Head to Student Store"
        content.body  = "Break starts in 5 minutes."
        content.sound = .default  // haptic fires per user's notification settings

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "asb-break-\(dayKey)",
                                                     content: content, trigger: trigger))
    }

    // 5 min before lunch STARTS — head to Student Store
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
}
