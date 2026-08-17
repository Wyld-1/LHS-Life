//
//  PhoneTabDock.swift
//  LHS Life
//
//  (Relocated from UI/AppDock.swift — same content, moved for organization.)
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
//  PhoneLayout has zero knowledge of which version is running.
//

import SwiftUI

struct AppDock: View {
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState
    var toolbarConfig: PhoneToolbarConfig = PhoneToolbarConfig()
    var mapResetToken: Int = 0
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
                toolbarConfig: toolbarConfig,
                mapResetToken: mapResetToken,
                onSameTabTap: onSameTabTap,
                onHomeworkTap: onHomeworkTap
            )
        } else {
            // iPhone iOS 17-25 only (iPad has its own layout entirely)
            LegacyTabDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                toolbarConfig: toolbarConfig,
                mapResetToken: mapResetToken,
                onSameTabTap: onSameTabTap,
                onHomeworkTap: onHomeworkTap
            )
        }
    }
}

// MARK: - iOS 26+: System liquid glass TabView

@available(iOS 26, *)
private struct SystemTabDock: View {
    @Binding var selectedTab: AppTab
    @Environment(CalendarUIState.self) private var uiState
    @Environment(UserSettings.self) private var settings
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState
    var toolbarConfig: PhoneToolbarConfig = PhoneToolbarConfig()
    var mapResetToken: Int = 0
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
            Tab(AppTab.events.title, systemImage: AppTab.events.iconName, value: AppTab.events) {
                EventsTabView()
                    .phoneToolbar(tab: .events, config: toolbarConfig)
            }
            if settings.showMapTab {
                Tab(AppTab.map.title, systemImage: AppTab.map.iconName, value: AppTab.map) {
                    MapTabView(resetToken: mapResetToken)
                        .phoneToolbar(tab: .map, config: toolbarConfig)
                }
            }
            Tab(AppTab.lunch.title, systemImage: AppTab.lunch.iconName, value: AppTab.lunch) {
                LunchTabView(webState: lunchState)
                    .phoneToolbar(tab: .lunch, config: toolbarConfig)
            }
            Tab(value: AppTab.powerschool) {
                PowerSchoolTabView(webState: powerschoolState)
                    .phoneToolbar(tab: .powerschool, config: toolbarConfig)
            } label: {
                Label(AppTab.powerschool.title, image: AppTab.powerschool.iconName)
            }
            Tab(value: AppTab.schoology) {
                SchoologyTabView(webState: schoologyState)
                    .phoneToolbar(tab: .schoology, config: toolbarConfig)
            } label: {
                Label(AppTab.schoology.title, image: AppTab.schoology.iconName)
            }
        }
        .tabBarMinimizeBehavior(uiState.viewMode == .day ? .onScrollDown : .never)
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
    @Environment(UserSettings.self) private var settings
    @Binding var selectedTab: AppTab
    let lunchState:       EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState:   EmbeddedWebState
    var toolbarConfig: PhoneToolbarConfig = PhoneToolbarConfig()
    var mapResetToken: Int = 0
    var onSameTabTap: (AppTab) -> Void = { _ in }
    var onHomeworkTap: () -> Void = {}

    private var tabs: [AppTab] { AppTab.dockTabs(showMap: settings.showMapTab) }

    var body: some View {
        ZStack {
            // Content — all always mounted so web views stay alive
            EventsTabView()
                .phoneToolbar(tab: .events, config: toolbarConfig)
                .opacity(selectedTab == .events      ? 1 : 0)
                .allowsHitTesting(selectedTab == .events)
            // Map is the one exception to "always mounted": it's gated on the
            // same settings.showMapTab the iOS 26 Tab and the iPad sidebar row
            // use, and it holds no web session that would be expensive to
            // rebuild, so mounting on demand costs nothing.
            if settings.showMapTab {
                MapTabView(resetToken: mapResetToken)
                    .phoneToolbar(tab: .map, config: toolbarConfig)
                    .opacity(selectedTab == .map     ? 1 : 0)
                    .allowsHitTesting(selectedTab == .map)
            }
            LunchTabView(webState: lunchState)
                .phoneToolbar(tab: .lunch, config: toolbarConfig)
                .opacity(selectedTab == .lunch       ? 1 : 0)
                .allowsHitTesting(selectedTab == .lunch)
            PowerSchoolTabView(webState: powerschoolState)
                .phoneToolbar(tab: .powerschool, config: toolbarConfig)
                .opacity(selectedTab == .powerschool ? 1 : 0)
                .allowsHitTesting(selectedTab == .powerschool)
            SchoologyTabView(webState: schoologyState)
                .phoneToolbar(tab: .schoology, config: toolbarConfig)
                .opacity(selectedTab == .schoology   ? 1 : 0)
                .allowsHitTesting(selectedTab == .schoology)

            // Dock + homework button share ONE row, so they cannot drift
            // vertically relative to each other — they resolve to the same
            // LS.dockHeight and the HStack centers them against each other.
            // Previously the FAB lived in PhoneLayout with its own
            // .padding(.bottom, LS.xxl) while the dock used LS.sm, which is
            // exactly why they sat at different heights.
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: LS.sm) {
                    LegacyDockBar(
                        tabs: tabs,
                        selectedTab: $selectedTab,
                        onSameTabTap: onSameTabTap
                    )
                    HomeworkFAB(action: onHomeworkTap)
                }
                .padding(.horizontal, LS.md)
                .padding(.bottom, LS.lg)
            }
            // Resolves against the physical screen edge rather than the home
            // indicator's safe area — same idiom iPadHomeworkFAB uses to sit
            // near the true hardware corner. LS.lg (24) rather than LS.md (16):
            // the indicator occupies roughly the bottom 21pt, so 16 would put
            // the dock's lower edge inside it.
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: settings.showMapTab) { _, shown in
            // Turning Map off while standing on it would otherwise strand the
            // user on an unmounted tab with no way back.
            if !shown && selectedTab == .map {
                withAnimation(.lsSnappy) { selectedTab = .events }
            }
        }
    }
}

private struct LegacyDockBar: View {
    let tabs: [AppTab]
    @Binding var selectedTab: AppTab
    var onSameTabTap: (AppTab) -> Void = { _ in }

    /// Drives the sliding selection capsule. Namespace lives on the bar so
    /// all buttons share one geometry group.
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.rawValue) { tab in
                LegacyDockButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    indicator: indicator
                ) {
                    if tab == selectedTab {
                        // Already on this tab — treat as home
                        onSameTabTap(tab)
                    } else {
                        withAnimation(.lsSnappy) { selectedTab = tab }
                    }
                }
            }
        }
        .padding(.horizontal, LS.sm)
        .frame(height: LS.dockHeight)
        .frame(maxWidth: .infinity)
        .background {
            // Capsule, not a rounded rect: with the dock now sitting close to
            // the physical bottom edge, a fully-rounded end reads better
            // against the bezel than a squircle, and it matches the selection
            // indicator inside it. (This trades away the concentric-corner
            // approximation — a capsule's radius is always half its height.)
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    // Was hardcoded white — invisible in dark, a bright rim in
                    // light. lsPrimary flips with appearance.
                    Capsule()
                        .strokeBorder(Color.lsPrimary.opacity(0.06), lineWidth: 0.5)
                }
                .shadow(
                    color: .black.opacity(LS.shadowOpacity),
                    radius: LS.shadowRadius,
                    y: LS.shadowY
                )
        }
    }
}

private struct LegacyDockButton: View {
    let tab: AppTab
    let isSelected: Bool
    let indicator: Namespace.ID
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
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                            .frame(height: 20)
                    }
                }
                .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)

                Text(tab.title)
                    .font(.lsLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? Color.lsBlue : Color.lsSecondary)
            }
            // Flexible, not a fixed 64pt: with Map enabled this bar carries
            // five tabs, and fixed widths overflow the screen once the
            // homework button takes its share of the row.
            .frame(maxWidth: .infinity)
            .frame(height: LS.dockHeight - LS.sm)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.lsBlue.opacity(0.14))
                        .matchedGeometryEffect(id: "dockIndicator", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.lsSnappy, value: isSelected)
    }
}
