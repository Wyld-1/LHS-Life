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
    @State private var previousTab   = AppTab.events
    @State private var showSettings  = false
    @State private var showHomework  = false
    @State private var isLaunching   = true   // true until all web states are ready

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

    // Progress: calendar load (0.33) + each web state (0.22 each)
    private var launchProgress: Double {
        var p = store.events.isEmpty ? 0.0 : 0.34
        if lunchState.isReady       { p += 0.22 }
        if powerschoolState.isReady { p += 0.22 }
        if schoologyState.isReady   { p += 0.22 }
        return min(p, 1.0)
    }

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
                schoologyState: schoologyState,
                onSameTabTap: { tab in
                    // Tapping the active tab acts as a home button
                    switch tab {
                    case .powerschool: powerschoolState.reload()
                    case .schoology:   schoologyState.reload()
                    case .lunch:       lunchState.reload()
                    default: break
                    }
                }
            )

            // Layer 1 — Floating chrome
            VStack {
                ScheduleHeader(showSettings: $showSettings, onPillTap: {
                    withAnimation(.lsSnappy) { selectedTab = .events }
                })
                .padding(.horizontal, LS.md)

                Spacer()

                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: LS.sm) {
                        if selectedTab == .powerschool {
                            WebNavButtons(
                                webState: powerschoolState,
                                onHomeTap: { powerschoolState.reload() }
                            )
                        } else if selectedTab == .schoology {
                            WebNavButtons(
                                webState: schoologyState,
                                onHomeTap: { schoologyState.reload() }
                            )
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

            // Homework popup
            if showHomework {
                HomeworkPopup(onDismiss: { withAnimation(.lsSpring) { showHomework = false } })
                    .environment(store)
                    .environment(settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }

            // Launch screen — blocks interaction until everything is ready
            if isLaunching {
                LaunchScreen(progress: launchProgress)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .background(Color.lsBackground)
        .onChange(of: launchProgress) { _, progress in
            if progress >= 1.0 && isLaunching {
                withAnimation(.easeInOut(duration: 0.4)) { isLaunching = false }
            }
        }
        .onChange(of: selectedTab) { old, new in
            if new == .homework {
                // Snap back to previous tab immediately — content never changes.
                // The popup floats over whatever tab was active.
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
