//
//  AppIntentSupport.swift
//  LHS Life
//
//  Shared readiness guard. App Intents run out-of-process from the UI, so
//  there's no guarantee ContentView's `.task` — which normally kicks off
//  CalendarStore.loadAll() — has ever run before Siri invokes an intent,
//  especially on a cold launch triggered directly by Siri rather than by
//  opening the app. Every Tier 1 intent calls this first so it never
//  silently answers (or hangs) from an empty, never-loaded store.
//

import Foundation
import AppIntents

enum AppIntentSupport {
    @MainActor
    static func ensureDataLoaded(store: CalendarStore, settings: UserSettings) async {
        guard settings.accessApproved else { return }
        guard store.events.isEmpty else { return }
        await store.loadAll()
    }

    static let setupIncompleteDialog: IntentDialog =
        "LHS Life hasn't finished setup yet — open the app to finish onboarding first."
}
