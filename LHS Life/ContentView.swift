//
//  ContentView.swift
//  LHS Life
//

import SwiftUI

struct ContentView: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        if settings.accessApproved {
            AppTabContainer()
        } else {
            AccessGuardView(settings: settings)
                .transition(.opacity)
        }
    }
}

#Preview {
    ContentView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
