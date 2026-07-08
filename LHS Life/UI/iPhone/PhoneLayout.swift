//
//  PhoneLayout.swift
//  LHS Life
//
//  (Extracted from AppTabContainer.swift's old iPhoneLayout computed
//  property — same body, now a standalone view taking its dependencies as
//  parameters/bindings instead of reading container state directly.)
//
//  ZStack with PhoneTabDock behind, PhoneHeaderRow + legacy homework FAB
//  floating on top.
//

import SwiftUI
internal import WebKit

struct PhoneLayout: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    @Binding var selectedTab: AppTab
    @Binding var showSettings: Bool
    @Binding var showHomework: Bool
    let isLaunching: Bool
    let launchProgress: Double
    let calendarUI: CalendarUIState
    let lunchState: EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState: EmbeddedWebState

    private var showBadge: Bool {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let state = APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
        if case .none = state { return false }
        return !settings.apBadgeCleared
    }

    var body: some View {
        ZStack {
            AppDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                onSameTabTap: { tab in
                    switch tab {
                    case .events:      calendarUI.goToToday()
                    case .powerschool: powerschoolState.reload()
                    case .schoology:   schoologyState.reload()
                    case .lunch:       lunchState.reload()
                    default: break
                    }
                },
                onHomeworkTap: {
                    HapticEngine.shared.bump()
                    withAnimation(.lsSpring) { showHomework = true }
                }
            )
            .environment(calendarUI)

            VStack {
                PhoneHeaderRow(
                    selectedTab: selectedTab,
                    cycleLabel: calendarUI.zoomOutLabel,
                    onCycle: { calendarUI.zoomOutAction() },
                    canGoBack: selectedTab == .powerschool ? powerschoolState.canGoBack : schoologyState.canGoBack,
                    onBack: {
                        if selectedTab == .powerschool { powerschoolState.webView?.goBack() }
                        else if selectedTab == .schoology { schoologyState.webView?.goBack() }
                    },
                    showSettingsBadge: showBadge,
                    onSettings: {
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
}
