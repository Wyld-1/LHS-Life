//
//  LHS-LifeApp.swift
//  LHS Life
//

import SwiftUI
import UserNotifications
import ActivityKit
import BackgroundTasks
import UIKit

@main
struct LaSalle_ScheduleApp: App {

    // .shared singletons — App Intents read the exact same instances via
    // CalendarStore.shared / RemindersService.shared, no AppDependencyManager
    // registration or timing race, and no more init()-time self-capture
    // workaround needed either.
    @State private var store    = CalendarStore.shared
    @State private var settings = UserSettings.shared

    init() {
        // BGProcessingTask handler MUST be registered before first scene connects
        BellTransitionService.register()

        // Start iCloud settings sync — pulls remote prefs before first render
        UserSettings.shared.startICloudSync()

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
