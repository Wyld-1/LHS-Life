//
//  AppTabContainer.swift
//  LHS Life
//
//  Single branch point at the top level: iPhone vs iPad.
//
//  iPhone — ZStack with floating pill+button at top, AppDock at bottom.
//  iPad   — System TabView (top bar) with pill as bottom accessory.
//

import SwiftUI

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

    private var showBadge: Bool {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let state = APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
        if case .none = state { return false }
        return !settings.apBadgeCleared
    }

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
        ZStack {
            AppDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                onSameTabTap: { tab in
                    switch tab {
                    case .powerschool: powerschoolState.reload()
                    case .schoology:   schoologyState.reload()
                    case .lunch:       lunchState.reload()
                    default: break
                    }
                }
            )
            .environment(calendarUI)

            VStack {
                ScheduleHeader(
                    actionIcon: .settings(showBadge: showBadge),
                    onAction: {
                        settings.apBadgeCleared = true
                        showSettings = true
                    },
                    onPillTap: { withAnimation(.lsSnappy) { selectedTab = .events } },
                    onEventTap: { event in
                        withAnimation(.lsSnappy) { selectedTab = .events }
                        calendarUI.navigateTo(event: event)
                    }
                )
                .padding(.horizontal, LS.md)

                Spacer()

                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: LS.sm) {
                        if selectedTab == .events {
                            FloatingNavButtons(role: .calendar(
                                onToday: { calendarUI.goToToday() },
                                isOnToday: Calendar.current.isDateInToday(calendarUI.selectedDate) && calendarUI.viewMode == .day,
                                zoomLabel: calendarUI.zoomOutLabel,
                                onZoom: { calendarUI.zoomOutAction() }
                            ))
                        } else if selectedTab == .powerschool {
                            FloatingNavButtons(role: .web(state: powerschoolState, onHome: { powerschoolState.reload() }))
                        } else if selectedTab == .schoology {
                            FloatingNavButtons(role: .web(state: schoologyState, onHome: { schoologyState.reload() }))
                        }
                        if #unavailable(iOS 26) {
                            HomeworkFAB {
                                HapticEngine.shared.bump()
                                withAnimation(.lsSpring) { showHomework = true }
                            }
                        }
                    }
                }
                .padding(.trailing, LS.md)
                .padding(.bottom, LS.xxl)
            }
            .safeAreaPadding(.bottom)
            .background(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color.lsBackground,            location: 0),
                        .init(color: Color.lsBackground,            location: 0.3),
                        .init(color: Color.lsBackground.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: LS.contentTopInset)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            if showHomework {
                HomeworkPopup(onDismiss: { withAnimation(.lsSpring) { showHomework = false } })
                    .environment(store)
                    .environment(settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }

            if isLaunching {
                LaunchScreen(progress: launchProgress)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .background(Color.lsBackground)
    }

    // MARK: - iPad Layout

    @ViewBuilder
    private var iPadLayout: some View {
        if #available(iOS 26, *) {
            iPadTabView
        } else {
            iPhoneLayout
        }
    }

    @available(iOS 26, *)
    private var iPadTabView: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Events", systemImage: "calendar", value: AppTab.events) {
                    EventsTabView()
                        .environment(calendarUI)
                        .overlay(alignment: .bottomTrailing) {
                            FloatingNavButtons(role: .calendar(
                                onToday: { calendarUI.goToToday() },
                                isOnToday: Calendar.current.isDateInToday(calendarUI.selectedDate) && calendarUI.viewMode == .day,
                                zoomLabel: calendarUI.zoomOutLabel,
                                onZoom: { calendarUI.zoomOutAction() }
                            ))
                            .padding(.trailing, LS.md)
                            .padding(.bottom, 120)
                        }
                }
                Tab("Order", systemImage: "fork.knife", value: AppTab.lunch) {
                    LunchTabView(webState: lunchState)
                }
                Tab(value: AppTab.powerschool) {
                    PowerSchoolTabView(webState: powerschoolState)
                        .overlay(alignment: .bottomTrailing) {
                            FloatingNavButtons(role: .web(state: powerschoolState, onHome: { powerschoolState.reload() }))
                            .padding(.trailing, LS.md)
                            .padding(.bottom, 120)
                        }
                } label: {
                    Label("Grades", image: "powerschool-logo")
                }
                Tab(value: AppTab.schoology) {
                    SchoologyTabView(webState: schoologyState)
                        .overlay(alignment: .bottomTrailing) {
                            FloatingNavButtons(role: .web(state: schoologyState, onHome: { schoologyState.reload() }))
                            .padding(.trailing, LS.md)
                            .padding(.bottom, 120)
                        }
                } label: {
                    Label("Schoology", image: "schoology-logo")
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(Color.lsBlue)
            // Settings button — top right
            .overlay(alignment: .topTrailing) {
                SettingsButton(showSettings: $showSettings, showBadge: showBadge)
                    .padding(.trailing, LS.md)
                    .padding(.top, LS.sm)
            }

            // Header + homework button — bottom, mirroring iPhone's top header
            VStack {
                Spacer()
                HStack {
                    ScheduleHeader(
                        actionIcon: .homework,
                        onAction: { withAnimation(.lsSpring) { showHomework = true } },
                        onPillTap: { withAnimation(.lsSnappy) { selectedTab = .events } },
                        onEventTap: { event in
                            withAnimation(.lsSnappy) { selectedTab = .events }
                            calendarUI.navigateTo(event: event)
                        }
                    )
                    .environment(settings)
                    .environment(store)
                }
                .padding(.horizontal, LS.md)
                .padding(.bottom, LS.sm)
                .safeAreaPadding(.bottom)
            }

            if showHomework {
                HomeworkPopup(onDismiss: { withAnimation(.lsSpring) { showHomework = false } })
                    .environment(store)
                    .environment(settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
            if isLaunching {
                LaunchScreen(progress: launchProgress)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
    }

}

// MARK: - Homework FAB (iPhone legacy only)

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
