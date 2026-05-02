//
//  NotificationService.swift
//  LaSalle Schedule
//
//  Schedules local notifications for professional dress days.
//  Sends the night before at 9:00 PM — before you leave in the morning.
//

import Foundation
import UserNotifications

enum NotificationService {

    private static let center = UNUserNotificationCenter.current()
    private static let categoryID = "PROFESSIONAL_DRESS"

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

    // MARK: - Schedule Professional Dress Notifications

    /// Scans upcoming events and schedules a 9 PM notification
    /// the evening before each professional dress day.
    static func scheduleProfessionalDressNotifications(for events: [SchoolEvent]) async {
        // Remove all previously scheduled dress notifications first
        center.removePendingNotificationRequests(withIdentifiers: existingDressIDs(from: events))

        guard await isAuthorized else { return }

        let dressEvents = events.filter { isProfessionalDressEvent($0) }

        for event in dressEvents {
            await scheduleNotification(for: event)
        }
    }

    // MARK: - Private

    private static let dressKeywords = [
        "professional dress", "formal dress", "mass attire",
        "dress uniform", "professional attire", "formal attire"
    ]

    static func isProfessionalDressEvent(_ event: SchoolEvent) -> Bool {
        let combined = (event.title + " " + (event.description ?? "")).lowercased()
        return dressKeywords.contains { combined.contains($0) }
    }

    private static func scheduleNotification(for event: SchoolEvent) async {
        // Notification fires at 9 PM the evening before the event
        let calendar = Calendar.current
        guard let evening = calendar.date(byAdding: .day, value: -1, to: event.startDate) else { return }

        var comps = calendar.dateComponents([.year, .month, .day], from: evening)
        comps.hour = 21
        comps.minute = 0
        comps.second = 0

        // Don't schedule notifications in the past
        guard let fireDate = calendar.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Professional Dress Tomorrow"
        content.body  = "LaSalle requires professional dress for \(event.title) tomorrow."
        content.sound = .default
        content.categoryIdentifier = categoryID

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "dress-\(event.id)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[NotificationService] Failed to schedule for \(event.title): \(error)")
        }
    }

    private static func existingDressIDs(from events: [SchoolEvent]) -> [String] {
        events.map { "dress-\($0.id)" }
    }
}
