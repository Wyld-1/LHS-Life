//
//  EventsTabView.swift
//  LHS Life
//
//  Single ScrollView: inset → WeekStrip → EventsDayView.
//  EventsDayView is a pure fixed-height canvas — no internal scroll view.
//

import SwiftUI

struct EventsTabView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @State private var selectedDate: Date = Date()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {

                // Clears the floating pill
                Color.clear.frame(height: LS.contentTopInset)

                // Week strip — scrolls with the page
                WeekStrip(
                    selectedDate: $selectedDate,
                    onLabelTap: { /* open week/month grid — wired later */ }
                )
                .padding(.bottom, LS.sm)

                // Day canvas — fixed height, no internal scroll
                let dayKey   = DateFormatter.isoDay.string(from: selectedDate)
                let schedule = store.bellSchedules[dayKey]
                let events   = store.events(on: dayKey)

                EventsDayView(
                    date:     selectedDate,
                    schedule: schedule,
                    events:   events,
                    settings: settings
                )

                // Bottom clearance: tab bar + a little breathing room
                Color.clear.frame(height: LS.tabBarHeight + LS.lg)
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .background(Color.lsBackground)
    }
}

#Preview {
    EventsTabView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
