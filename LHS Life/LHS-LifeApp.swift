//
//  LHS-LifeApp.swift
//  LHS Life
//

import SwiftUI

@main
struct LaSalle_ScheduleApp: App {

    @State private var store    = CalendarStore()
    @State private var settings = UserSettings.shared

    init() {
        // Warm the Taptic Engine before any interaction happens.
        // prepare() is cheap and must be called on the main thread — App.init qualifies.
        Task { @MainActor in
            HapticEngine.shared.prepare()
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
