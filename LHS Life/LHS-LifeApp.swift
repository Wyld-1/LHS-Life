//
//  LHS-LifeApp.swift
//  LHS Life
//

import SwiftUI
import UserNotifications
import ActivityKit

@main
struct LaSalle_ScheduleApp: App {

    @State private var store    = CalendarStore()
    @State private var settings = UserSettings.shared

    init() {
        Task { @MainActor in
            HapticEngine.shared.prepare()
        }
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Register notification categories (abnormal schedule action button)
        NotificationService.registerCategories()
        Task {
            _ = await NotificationService.requestAuthorization()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                .task { await store.loadAll() }
        }
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler handler: @escaping () -> Void) {

        // Abnormal schedule — "Show Today's Schedule" action enables LA for today
        if response.actionIdentifier == NotificationService.enableLiveActivityActionID {
            Task { @MainActor in
                UserSettings.shared.enableLiveActivityForToday()
            }
        }

        // TeamReach deep link from ASB announcement
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }

        handler()
    }
}
