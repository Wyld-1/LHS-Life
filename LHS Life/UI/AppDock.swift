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
    var onSameTabTap: (AppTab) -> Void = { _ in }
    var onHomeworkTap: () -> Void = {}

    var body: some View {
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .phone {
            // iPhone iOS 26+: system liquid glass tab bar
            SystemTabDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                onSameTabTap: onSameTabTap,
                onHomeworkTap: onHomeworkTap
            )
        } else {
            // iPhone iOS 17-25, and iPad (iPad uses AppTabContainer's iPadLayout directly)
            LegacyTabDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                onSameTabTap: onSameTabTap
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
    var onSameTabTap: (AppTab) -> Void = { _ in }
    var onHomeworkTap: () -> Void = {}

    /// Custom selection binding: SwiftUI writes to `set` on every tab tap,
    /// including reselecting the already-active tab (newValue == current).
    /// That same-value write is our reselect signal. We do NOT touch the
    /// tab bar controller's delegate, so SwiftUI's own coordinator keeps
    /// driving selection — selectedTab stays live and the header updates.
    private var selection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                let isReselect = (newValue == selectedTab)
                if isReselect {
                    onSameTabTap(newValue)
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("Events", systemImage: "calendar", value: AppTab.events) {
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
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.lsBlue)
        .tabViewBottomAccessory {
            HomeworkAccessory(action: onHomeworkTap)
        }
    }
}

// MARK: - Homework Accessory (iOS 26+)
// Persistent one-tap "add homework" control, floating above the tab bar
// via the system tabViewBottomAccessory API — same mechanism as Apple
// Music's Now Playing bar. Always visible regardless of selected tab;
// tapping opens the same HomeworkPopup the legacy FAB opens.
@available(iOS 26, *)
private struct HomeworkAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.bump()
            action()
        } label: {
            HStack(spacing: LS.xs) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Add Homework")
                    .font(.lsHeadline)
            }
            .foregroundStyle(Color.lsPrimary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


private struct LegacyTabDock: View {
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState
    var onSameTabTap: (AppTab) -> Void = { _ in }

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
                    LegacyDockBar(selectedTab: $selectedTab, onSameTabTap: onSameTabTap)
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
    var onSameTabTap: (AppTab) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.dockTabs, id: \.rawValue) { tab in
                LegacyDockButton(tab: tab, isSelected: selectedTab == tab) {
                    if tab == selectedTab {
                        // Already on this tab — treat as home
                        HapticEngine.shared.tap()
                        onSameTabTap(tab)
                    } else {
                        HapticEngine.shared.tap()
                        withAnimation(.lsSnappy) { selectedTab = tab }
                    }
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
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(width: 64)
            .padding(.vertical, LS.xs)
        }
        .buttonStyle(.plain)
    }
}
