//
//  LaSalle_ScheduleApp.swift
//  LHS Life
//
//  Both CalendarStore and UserSettings are created exactly once here.
//  They're passed into the environment via .environment() (not .environmentObject())
//  which is the correct pattern for @Observable types in iOS 17+.
//

import SwiftUI

@main
struct LaSalle_ScheduleApp: App {

    // @State at the App level is the correct owner for @Observable singletons.
    // Unlike @StateObject, @State at App scope is safe — App is never rebuilt
    // by SwiftUI the way views are, so reinitialization is not a risk here.
    @State private var store = CalendarStore()
    @State private var settings = UserSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                .task { await store.loadAll() }
        }
    }
}
