//
//  AppDock.swift
//  LHS Life
//
//  The tab dock. One view, two implementations:
//
//  iOS 26+  — System TabView with liquid glass bar.
//             Apple builds and owns the chrome. We just declare tabs.
//             .tabBarMinimizeBehavior(.onScrollDown) collapses it on scroll.
//             Custom asset icons use Label("Title", image: "asset-name").
//
//  iOS 17–25 — Our custom frosted-glass capsule, bottom-left anchored.
//              Opacity-switches content. Identical buttons, different material.
//
//  AppTabContainer has zero knowledge of which version is running.
//

import SwiftUI

struct AppDock: View {
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState

    var body: some View {
        if #available(iOS 26, *) {
            SystemTabDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState
            )
        } else {
            LegacyTabDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState
            )
        }
    }
}

// MARK: - iOS 26+: System liquid glass TabView

@available(iOS 26, *)
private struct SystemTabDock: View {
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Events", systemImage: "bell.fill", value: AppTab.events) {
                EventsTabView()
            }
            Tab("Order", systemImage: "fork.knife", value: AppTab.lunch) {
                LunchTabView(webState: lunchState)
            }
            Tab(value: AppTab.powerschool) {
                PowerSchoolTabView(webState: powerschoolState)
            } label: {
                Label("Grades", image: "powerschool-logo")
            }
            Tab(value: AppTab.schoology) {
                SchoologyTabView(webState: schoologyState)
            } label: {
                Label("Schoology", image: "schoology-logo")
            }
            Tab(value: AppTab.homework, role: .search) {
                HomeworkSearchTab()
            } label: {
                Label("Homework", systemImage: "checklist")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.lsBlue)
    }
}

// MARK: - Homework Search Tab (iOS 26 only)
// Presented when the detached circle button is tapped.
// The system uses the .search role icon (magnifying glass) by default —
// we override the label to use our checklist icon instead.
@available(iOS 26, *)
private struct HomeworkSearchTab: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    var body: some View {
        HomeworkSheet()
    }
}


private struct LegacyTabDock: View {
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState

    var body: some View {
        ZStack {
            // Content — all four always mounted so web views stay alive
            EventsTabView()
                .opacity(selectedTab == .events      ? 1 : 0)
                .allowsHitTesting(selectedTab == .events)
            LunchTabView(webState: lunchState)
                .opacity(selectedTab == .lunch       ? 1 : 0)
                .allowsHitTesting(selectedTab == .lunch)
            PowerSchoolTabView(webState: powerschoolState)
                .opacity(selectedTab == .powerschool ? 1 : 0)
                .allowsHitTesting(selectedTab == .powerschool)
            SchoologyTabView(webState: schoologyState)
                .opacity(selectedTab == .schoology   ? 1 : 0)
                .allowsHitTesting(selectedTab == .schoology)

            // Tab bar — bottom left
            VStack {
                Spacer()
                HStack {
                    LegacyDockBar(selectedTab: $selectedTab)
                    Spacer()
                }
                .padding(.horizontal, LS.md)
                .padding(.bottom, LS.sm)
                .safeAreaPadding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LegacyDockBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.dockTabs, id: \.rawValue) { tab in
                LegacyDockButton(tab: tab, isSelected: selectedTab == tab) {
                    HapticEngine.shared.tap()
                    withAnimation(.lsSnappy) { selectedTab = tab }
                }
            }
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
    }
}

private struct LegacyDockButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Group {
                    if tab.isCustomAsset {
                        Image(tab.iconName)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    }
                }
                .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .animation(.lsSnappy, value: isSelected)

                Text(tab.title)
                    .font(.lsLabel)
                    .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)
            }
            .frame(width: 56)
            .padding(.vertical, LS.xs)
        }
        .buttonStyle(.plain)
    }
}
