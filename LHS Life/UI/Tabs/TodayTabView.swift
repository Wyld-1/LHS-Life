//
//  TodayTabView.swift
//  LHS Life
//

import SwiftUI

struct TodayTabView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LS.lg) {
                Color.clear.frame(height: 120)

                Text("Today")
                    .font(.lsDisplay)
                    .foregroundStyle(Color.lsPrimary)
                    .padding(.horizontal, LS.md)

                Text("Schedule timeline goes here.")
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
    TodayTabView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
