//
//  AppTabContainer.swift
//  LHS Life
//
//  Single branch point at the top level: iPhone vs iPad.
//
//  iPhone — PhoneLayout (UI/iPhone/): ZStack, floating header + tab dock.
//  iPad   — iPadRootView (UI/iPad/): NavigationSplitView, sidebar +
//           detail pane with a top-toolbar contextual button and a
//           persistent Homework FAB.
//

import SwiftUI
internal import WebKit

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable {
    case events      = 0
    case lunch       = 1
    case powerschool = 2
    case schoology   = 3
    case homework    = 4

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
        case .events:       return "calendar"
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

    static var dockTabs: [AppTab] { [.events, .lunch, .powerschool, .schoology] }
}

// MARK: - Root Container

struct AppTabContainer: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @State private var selectedTab  = AppTab.events
    @State private var previousTab  = AppTab.events
    @State private var showSettings = false
    @State private var showHomework = false
    @State private var isLaunching  = true
    @State private var calendarUI   = CalendarUIState()

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

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var launchProgress: Double {
        var p = store.events.isEmpty ? 0.0 : 0.34
        if lunchState.isReady       { p += 0.22 }
        if powerschoolState.isReady { p += 0.22 }
        if schoologyState.isReady   { p += 0.22 }
        return min(p, 1.0)
    }

    var body: some View {
        Group {
            if isPhone { iPhoneLayout } else { iPadLayout }
        }
        .onChange(of: launchProgress) { _, progress in
            if progress >= 1.0 && isLaunching {
                withAnimation(.easeInOut(duration: 0.4)) { isLaunching = false }
            }
        }
        .onChange(of: selectedTab) { _, new in
            if new == .homework {
                selectedTab = previousTab
                withAnimation(.lsSpring) { showHomework = true }
            } else {
                previousTab = new
            }
        }
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
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        PhoneLayout(
            selectedTab: $selectedTab,
            showSettings: $showSettings,
            showHomework: $showHomework,
            isLaunching: isLaunching,
            launchProgress: launchProgress,
            calendarUI: calendarUI,
            lunchState: lunchState,
            powerschoolState: powerschoolState,
            schoologyState: schoologyState
        )
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        iPadRootView(
            selectedTab: $selectedTab,
            showSettings: $showSettings,
            showHomework: $showHomework,
            isLaunching: isLaunching,
            launchProgress: launchProgress,
            calendarUI: calendarUI,
            lunchState: lunchState,
            powerschoolState: powerschoolState,
            schoologyState: schoologyState
        )
    }

}

#Preview {
    AppTabContainer()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
