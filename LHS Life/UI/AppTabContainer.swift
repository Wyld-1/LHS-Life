//
//  AppTabContainer.swift
//  LHS Life
//
//  Single branch point at the top level: iPhone vs iPad.
//
//  iPhone — ZStack with floating pill+button at top, AppDock at bottom.
//           Completely unchanged from the original design.
//
//  iPad   — System TabView (top bar, Apple's preferred layout) with:
//             • ScheduleHeaderPill as .tabViewBottomAccessory (like Music's Now Playing)
//             • SettingsButton as .toolbar item (top-right, always visible)
//           No floating ZStack chrome on iPad — the system owns the layout.
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

    static var dockTabs: [AppTab] { [.events, .lunch, .powerschool, .schoology] }
}

// MARK: - Root Container

struct AppTabContainer: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @State private var selectedTab   = AppTab.events
    @State private var previousTab   = AppTab.events
    @State private var showSettings  = false
    @State private var showHomework  = false
    @State private var isLaunching   = true

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

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
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
            if isPhone {
                iPhoneLayout
            } else {
                iPadLayout
            }
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
    // Exactly as before — floating ZStack with pill+button at top, dock at bottom.
    // Zero changes from the original iPhone design.

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

            VStack {
                // Pill + settings button together at the top
                ScheduleHeader(showSettings: $showSettings, onPillTap: {
                    withAnimation(.lsSnappy) { selectedTab = .events }
                })
                .padding(.horizontal, LS.md)

                Spacer()

                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: LS.sm) {
                        if selectedTab == .powerschool {
                            WebNavButtons(webState: powerschoolState,
                                          onHomeTap: { powerschoolState.reload() })
                        } else if selectedTab == .schoology {
                            WebNavButtons(webState: schoologyState,
                                          onHomeTap: { schoologyState.reload() })
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
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)

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
    // System TabView at top (Apple's preferred iPad pattern).
    // Pill as bottom accessory — like Apple Music's Now Playing bar.
    // Settings button in toolbar — always top-right.

    @ViewBuilder
    private var iPadLayout: some View {
        if #available(iOS 26, *) {
            iPadTabView
        } else {
            // iPad on iOS 17-25: use the legacy ZStack layout
            // (iOS 26 is the only version where tabViewBottomAccessory is available)
            iPhoneLayout
        }
    }

    @available(iOS 26, *)
    private var iPadTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Events", systemImage: "bell.fill", value: AppTab.events) {
                EventsTabView()
            }
            Tab("Order", systemImage: "fork.knife", value: AppTab.lunch) {
                LunchTabView(webState: lunchState)
            }
            Tab(value: AppTab.powerschool) {
                PowerSchoolTabView(webState: powerschoolState)
                    .overlay(alignment: .bottomTrailing) {
                        WebNavButtons(webState: powerschoolState,
                                      onHomeTap: { powerschoolState.reload() })
                        .padding(.trailing, LS.md)
                        .padding(.bottom, LS.xxl)
                    }
            } label: {
                Label("Grades", image: "powerschool-logo")
            }
            Tab(value: AppTab.schoology) {
                SchoologyTabView(webState: schoologyState)
                    .overlay(alignment: .bottomTrailing) {
                        WebNavButtons(webState: schoologyState,
                                      onHomeTap: { schoologyState.reload() })
                        .padding(.trailing, LS.md)
                        .padding(.bottom, LS.xxl)
                    }
            } label: {
                Label("Schoology", image: "schoology-logo")
            }
            Tab(value: AppTab.homework, role: .search) {
                iPadHomeworkContent
            } label: {
                Label("Homework", systemImage: "checklist")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.lsBlue)
        // Pill lives at the bottom — mirrors Apple Music's Now Playing bar
        .tabViewBottomAccessory {
            ScheduleHeaderPill(onPillTap: {
                withAnimation(.lsSnappy) { selectedTab = .events }
            })
            .padding(.horizontal, LS.md)
            .padding(.vertical, LS.xs)
        }
        // Settings button always top-right in the toolbar
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton(showSettings: $showSettings)
            }
        }
        .overlay {
            if isLaunching {
                LaunchScreen(progress: launchProgress)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
    }

    @available(iOS 26, *)
    private var iPadHomeworkContent: some View {
        ZStack {
            Color.lsBackground.ignoresSafeArea()
            HomeworkPopup(onDismiss: { selectedTab = previousTab })
                .environment(store)
                .environment(settings)
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
