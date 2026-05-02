//
//  AppTabContainer.swift
//  LHS Life
//
//  LunchWebState lives here — at the container level — so the WKWebView
//  exists for the entire app session. Tapping the Order tab just reveals
//  an already-loading view. The tab bar has nothing to do with network loading.
//

import SwiftUI

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable {
    case today  = 0
    case events = 1
    case lunch  = 2

    var title: String {
        switch self {
        case .today:  return "Today"
        case .events: return "Calendar"
        case .lunch:  return "Order"
        }
    }

    var icon: String {
        switch self {
        case .today:  return "bell.fill"
        case .events: return "calendar"
        case .lunch:  return "fork.knife"
        }
    }
}

// MARK: - Root Tab Container

struct AppTabContainer: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @State private var selectedTab: AppTab = .today
    @State private var showSettings = false

    // LunchWebState lives here so the WKWebView survives tab switches.
    // It's created once when AppTabContainer first appears, loads in the
    // background, and is passed into LunchTabView as a plain reference.
    @State private var lunchWebState = LunchWebState()

    var body: some View {
        let _ = Self._printChanges()  // TELEMETRY: remove before release
        ZStack(alignment: .top) {
            Color.lsBackground
                .ignoresSafeArea()

            tabContent
                .ignoresSafeArea()

            ScheduleHeader(showSettings: $showSettings)
                .padding(.horizontal, LS.md)
                .padding(.top, LS.xs)
        }
        .task { lunchWebState.initialize() }  // start loading immediately, off the layout pass
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(settings: settings)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.lsSurface)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 26, *) {
            iOS26TabView(selectedTab: $selectedTab, lunchWebState: lunchWebState)
        } else {
            CustomTabView(selectedTab: $selectedTab, lunchWebState: lunchWebState)
        }
    }
}

// MARK: - iOS 26+

@available(iOS 26, *)
private struct iOS26TabView: View {
    @Binding var selectedTab: AppTab
    let lunchWebState: LunchWebState

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.today.title,  systemImage: AppTab.today.icon,  value: AppTab.today)  { TodayTabView() }
            Tab(AppTab.events.title, systemImage: AppTab.events.icon, value: AppTab.events) { EventsTabView() }
            Tab(AppTab.lunch.title,  systemImage: AppTab.lunch.icon,  value: AppTab.lunch)  { LunchTabView(webState: lunchWebState) }
        }
        .tint(Color.lsBlue)
    }
}

// MARK: - Custom Tab View (iOS 17–25)

private struct CustomTabView: View {
    @Binding var selectedTab: AppTab
    let lunchWebState: LunchWebState

    var body: some View {
        let _ = Self._printChanges()  // TELEMETRY: remove before release
        ZStack {
            TodayTabView()
                .opacity(selectedTab == .today  ? 1 : 0)
                .allowsHitTesting(selectedTab == .today)
            EventsTabView()
                .opacity(selectedTab == .events ? 1 : 0)
                .allowsHitTesting(selectedTab == .events)
            // LunchTabView receives the already-initialized webState — zero work on tab switch
            LunchTabView(webState: lunchWebState)
                .opacity(selectedTab == .lunch  ? 1 : 0)
                .allowsHitTesting(selectedTab == .lunch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            CustomTabBar(selectedTab: $selectedTab)
        }
    }
}

// MARK: - Floating Tab Bar

private struct CustomTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                TabBarButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.lsSnappy) { selectedTab = tab }
                }
            }
        }
        .padding(.horizontal, LS.lg)
        .padding(.vertical, LS.sm)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
        .padding(.horizontal, LS.xxl)
        .padding(.bottom, LS.sm)
        .safeAreaPadding(.bottom)
    }
}

private struct TabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.lsSnappy, value: isSelected)
                Text(tab.title)
                    .font(.lsLabel)
                    .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LS.xs)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppTabContainer()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
