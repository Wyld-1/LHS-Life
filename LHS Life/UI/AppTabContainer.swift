//
//  AppTabContainer.swift
//  LHS Life
//
//  Two-level ZStack:
//    Layer 0 — tab content
//    Layer 1 — floating chrome (header top, dock+FAB bottom)
//
//  AppDock owns the iOS version branch entirely.
//  AppTabContainer has zero #available checks.
//

import SwiftUI

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable {
    case events      = 0
    case lunch       = 1
    case powerschool = 2
    case schoology   = 3
    case homework    = 4  // iOS 26: becomes the detached search-role circle

    var title: String {
        switch self {
        case .events:       return "Events"
        case .lunch:        return "Order"
        case .powerschool:  return "Grades"
        case .schoology:    return "Schoology"
        case .homework:     return "Homework"
        }
    }

    var iconName: String {
        switch self {
        case .events:       return "bell.fill"
        case .lunch:        return "fork.knife"
        case .powerschool:  return "powerschool-logo"
        case .schoology:    return "schoology-logo"
        case .homework:     return "checklist"
        }
    }

    var isCustomAsset: Bool {
        switch self {
        case .powerschool, .schoology: return true
        default: return false
        }
    }

    // Legacy dock only shows the four main tabs — homework is iOS 26 search role only
    static var dockTabs: [AppTab] { [.events, .lunch, .powerschool, .schoology] }
}

// MARK: - Root Container

struct AppTabContainer: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @State private var selectedTab  = AppTab.events
    @State private var showSettings = false
    @State private var showHomework = false

    @State private var lunchState = EmbeddedWebState(
        url: URL(string: "https://lhs.plan.tech/lunch/")!,
        siteName: "Lunch Order",
        injectDarkCSS: true
    )
    @State private var powerschoolState = EmbeddedWebState(
        url: URL(string: "https://lasalleyakima.powerschool.com/guardian/home.html?_userTypeHint=student#")!,
        siteName: "PowerSchool"
    )
    @State private var schoologyState = EmbeddedWebState(
        url: URL(string: "https://lasalleyakima.schoology.com/home")!,
        siteName: "Schoology"
    )

    var body: some View {
        ZStack {

            // MARK: Layer 0 — Content
            // AppDock owns the tab switching on both OS versions.
            // On iOS 26 the system TabView handles selection and gestures.
            // On legacy we opacity-switch here and AppDock drives selectedTab.
            AppDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState
            )

            // MARK: Layer 1 — Floating chrome
            VStack {
                // Top row: pill header (settings button is inside ScheduleHeader)
                ScheduleHeader(showSettings: $showSettings)
                    .padding(.horizontal, LS.md)

                Spacer()

                // Bottom row: FAB is only needed on legacy.
                // On iOS 26 the .search role tab renders the detached circle.
                if #unavailable(iOS 26) {
                    HStack {
                        Spacer()
                        HomeworkFAB { showHomework = true }
                    }
                    .padding(.horizontal, LS.md)
                    .padding(.bottom, LS.sm)
                }
            }
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)
        }
        .background(Color.lsBackground)
        .task {
            async let l: () = lunchState.initialize()
            async let p: () = powerschoolState.initialize()
            async let s: () = schoologyState.initialize()
            _ = await (l, p, s)
        }
        .background {
            SettingsSheetView(settings: settings)
                .frame(width: 0, height: 0).opacity(0)
                .allowsHitTesting(false).clipped()
            ColorPickerPrewarm()
                .frame(width: 0, height: 0).opacity(0)
                .allowsHitTesting(false).clipped()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(settings: settings)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.lsSurface)
        }
        .sheet(isPresented: $showHomework) {
            HomeworkSheet()
                .environment(store)
                .environment(settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.lsSurface)
        }
    }
}

// MARK: - Homework FAB

private struct HomeworkFAB: View {
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.bump()
            action()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(Color.lsBlue)
                        .shadow(color: Color.lsBlue.opacity(0.4), radius: 12, y: 4)
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppTabContainer()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
