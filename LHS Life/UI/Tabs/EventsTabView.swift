//
//  EventsTabView.swift
//  LHS Life
//
//  Content scrolls full-screen behind the floating header.
//  A gradient fade at the top creates a soft blend under the pill.
//  Safe area insets ensure content doesn't hide under the dock.
//

import SwiftUI

struct EventsTabView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // MARK: Scrollable content — fills entire screen
                ScrollView {
                    VStack(alignment: .leading, spacing: LS.lg) {
                        // Space behind the header — content scrolls under it
                        Color.clear.frame(height: 120)

                        Text("Today")
                            .font(.lsDisplay)
                            .foregroundStyle(Color.lsPrimary)
                            .padding(.horizontal, LS.md)

                        Text("Schedule timeline and calendar go here.")
                            .font(.lsBody)
                            .foregroundStyle(Color.lsSecondary)
                            .padding(.horizontal, LS.md)

                        // Bottom clearance: safe area + dock height + FAB
                        Color.clear.frame(height: geo.safeAreaInsets.bottom + 100)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .ignoresSafeArea()

                // MARK: Top gradient — fades content behind the header pill
                // Starts fully opaque at the very top, transparent ~100pt down.
                // This means the header always reads clearly and content
                // gracefully disappears as it scrolls up behind it.
                LinearGradient(
                    stops: [
                        .init(color: Color.lsBackground, location: 0),
                        .init(color: Color.lsBackground, location: 0.35),
                        .init(color: Color.lsBackground.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.safeAreaInsets.top + 96)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)  // passes taps through to content below
            }
        }
        .background(Color.lsBackground)
        .ignoresSafeArea()
    }
}

#Preview {
    EventsTabView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
