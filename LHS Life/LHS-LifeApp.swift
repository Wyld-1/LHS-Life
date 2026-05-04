//
//  LHS-LifeApp.swift
//  LHS Life
//

import SwiftUI
import UserNotifications

@main
struct LaSalle_ScheduleApp: App {

    @State private var store    = CalendarStore()
    @State private var settings = UserSettings.shared

    init() {
        Task { @MainActor in
            HapticEngine.shared.prepare()
        }
        // Handle notification taps (e.g. TeamReach deep link from ASB announcement)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
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

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    // Handle tap — open TeamReach if the notification carries a URL
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler handler: @escaping () -> Void) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
        handler()
    }
}
