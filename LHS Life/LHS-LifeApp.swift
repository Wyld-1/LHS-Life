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

    @State private var store    = CalendarStore()
    @State private var settings = UserSettings.shared

    init() {
        // BGProcessingTask handler MUST be registered before first scene connects
        BellTransitionService.register()

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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    guard settings.accessApproved else { return }
                    let dayKey = DateFormatter.isoDay.string(from: Date())
                    LiveActivityService.shared.updateNow(
                        schedule: store.bellSchedules[dayKey],
                        settings: settings
                    )
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
