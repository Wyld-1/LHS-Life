//
//  LHS-LifeApp.swift
//  LHS Life
//

import SwiftUI
import UserNotifications
import ActivityKit
import BackgroundTasks
import UIKit
import AppIntents

@main
struct LaSalle_ScheduleApp: App {

    // .shared singletons — App Intents read the exact same instances via
    // CalendarStore.shared / RemindersService.shared, no AppDependencyManager
    // registration or timing race, and no more init()-time self-capture
    // workaround needed either.
    @State private var store    = CalendarStore.shared
    @State private var settings = UserSettings.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // BGProcessingTask handler MUST be registered before first scene connects
        BellTransitionService.register()

        // Register shared singletons with AppDependencyManager so App Intents
        // running in the extension process get the same instances. Without this,
        // each snippet intent gets a fresh, empty CalendarStore — loadAll() then
        // races against Siri's rendering timeout and the content card fails to
        // load. NavigationIntents (openAppWhenRun: true) are unaffected since
        // they run in the main process; the five snippet-returning intents are
        // the ones that need this registration.
        AppDependencyManager.shared.add(dependency: CalendarStore.shared)
        AppDependencyManager.shared.add(dependency: UserSettings.shared)

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
                    startLiveActivity()
                }
                .onChange(of: settings.accessApproved) { _, approved in
                    guard approved else { return }
                    Task {
                        await store.loadAll()
                        startLiveActivity()
                    }
                }
                // Foreground is where the notification-tap confirmation gets
                // resolved. The notification action can fire while the app is
                // backgrounded or not running at all, so the overlay can't be
                // shown from the delegate — it's deferred to here, when there
                // is actually a screen to show it on.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    startLiveActivity()
                    resolvePendingConfirmation()
                }
        }
    }

    @MainActor
    private func startLiveActivity() {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        LiveActivityService.shared.startIfNeeded(
            schedule: store.bellSchedules[dayKey],
            settings: settings
        )
    }

    @MainActor
    private func resolvePendingConfirmation() {
        guard LiveActivityService.shared.pendingStartConfirmation else { return }
        LiveActivityService.shared.pendingStartConfirmation = false

        // Only confirm what actually happened. The Live Activity lives on the
        // Lock Screen, so the user can't verify a claim made here — which
        // makes a wrong "started" worse than saying nothing.
        if LiveActivityService.shared.isRunning {
            ConfirmationState.shared.show("Live Activities started")
        } else {
            ConfirmationState.shared.show(
                LiveActivityService.shared.lastStartFailure ?? "Couldn't start Live Activities",
                style: .warning
            )
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
        // Two ways in, and they must behave identically:
        //   1. The "Show Today's Schedule" action button.
        //   2. Tapping the notification BODY — the default action.
        //
        // Both the abnormal-schedule and the "School starts soon" reminder
        // use this category, and both bodies say "Tap to…", so a plain tap
        // promising action and delivering none was a broken promise. The
        // default action previously fell through and just opened the app.
        let isActionButton =
            response.actionIdentifier == NotificationService.enableLiveActivityActionID
        let isBodyTap =
            response.actionIdentifier == UNNotificationDefaultActionIdentifier &&
            response.notification.request.content.categoryIdentifier
                == NotificationService.abnormalScheduleCategoryID

        if isActionButton || isBodyTap {
            Task { @MainActor in Self.beginLiveActivityFromNotification() }
        }
        handler()
    }

    /// Enables Live Activities for today, attempts the start, and flags the
    /// confirmation for the next foreground.
    @MainActor
    private static func beginLiveActivityFromNotification() {
        UserSettings.shared.enableLiveActivityForToday()
        // Flag first, then attempt the start. Whichever path gets there —
        // this one, or ContentView's .task on a cold launch — the flag is
        // resolved on the next foreground.
        LiveActivityService.shared.pendingStartConfirmation = true

        let dayKey = DateFormatter.isoDay.string(from: Date())
        LiveActivityService.shared.startIfNeeded(
            schedule: CalendarStore.shared.bellSchedules[dayKey],
            settings: UserSettings.shared
        )
    }
}
