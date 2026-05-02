//
//  EventsTabView.swift
//  LHS Life
//

import SwiftUI

struct EventsTabView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LS.lg) {
                Color.clear.frame(height: 120)

                Text("Events")
                    .font(.lsDisplay)
                    .foregroundStyle(Color.lsPrimary)
                    .padding(.horizontal, LS.md)

                Text("Calendar grid goes here.")
                    .font(.lsBody)
                    .foregroundStyle(Color.lsSecondary)
                    .padding(.horizontal, LS.md)

                Color.clear.frame(height: 100)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lsBackground)
        .ignoresSafeArea()
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    EventsTabView()
        .environment(CalendarStore())
}
