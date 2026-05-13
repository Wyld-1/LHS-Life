//
//  LHS-LifeApp.swift
//  LHS Life
//
//  App entry point — matched to LHS Live's working structure exactly.
//

import SwiftUI
import UserNotifications
import ActivityKit

@main
struct LaSalle_ScheduleApp: App {

    @State private var store    = CalendarStore()
    @State private var settings = UserSettings.shared

    init() {
        Task { @MainActor in HapticEngine.shared.prepare() }
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationService.registerCategories()
        Task { _ = await NotificationService.requestAuthorization() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                .task {
                    guard settings.accessApproved else { return }
                    await store.loadAll()
                    let dayKey = DateFormatter.isoDay.string(from: Date())
                    LiveActivityService.shared.startIfNeeded(
                        schedule: store.bellSchedules[dayKey],
                        settings: settings
                    )
                }
                .onChange(of: settings.accessApproved) { _, approved in
                    guard approved else { return }
                    Task {
                        await store.loadAll()
                        let dayKey = DateFormatter.isoDay.string(from: Date())
                        LiveActivityService.shared.startIfNeeded(
                            schedule: store.bellSchedules[dayKey],
                            settings: settings
                        )
                    }
                }
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

        if response.actionIdentifier == NotificationService.enableLiveActivityActionID {
            Task { @MainActor in UserSettings.shared.enableLiveActivityForToday() }
        }

        handler()
    }
}
