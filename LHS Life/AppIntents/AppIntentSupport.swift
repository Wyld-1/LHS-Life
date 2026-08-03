//
//  AppIntentSupport.swift
//  LHS Life
//
//  Shared readiness guard for App Intents.
//
//  App Intents that return snippet views run out-of-process in the App
//  Intents extension. Each gets a fresh CalendarStore instance unless
//  AppDependencyManager is used. We now register both singletons in
//  LHS-LifeApp.init() via AppDependencyManager.shared.add(dependency:),
//  so @Dependency resolves to the same shared instance in both the main
//  app process and the extension process.
//
//  IMPORTANT: ensureDataLoaded must complete quickly. The system may run
//  perform() several times (dark mode changes, etc.) and will time out if
//  a full network load blocks rendering. The guard below skips loadAll()
//  if the store already has events — stale-but-present data is fine for
//  a quick Siri answer; the app itself will refresh on next foreground.
//

import Foundation
import AppIntents

enum AppIntentSupport {
    @MainActor
    static func ensureDataLoaded(store: CalendarStore, settings: UserSettings) async {
        guard settings.accessApproved else { return }
        // Skip the full network load if we already have any events —
        // a Siri snippet rendering quickly with slightly stale data is
        // better than timing out waiting for a fresh fetch.
        guard store.events.isEmpty else { return }
        await store.loadAll()
    }

    static let setupIncompleteDialog: IntentDialog =
        "LHS Life hasn't finished setup yet — open the app to finish onboarding first."
}
