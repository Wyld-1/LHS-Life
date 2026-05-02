//
//  ContentView.swift
//  LHS Life
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        AppTabContainer()
    }
}

#Preview {
    ContentView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
