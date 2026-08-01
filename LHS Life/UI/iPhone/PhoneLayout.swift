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

    /// Everything the per-tab nav bar needs. Built here (where store,
    /// settings and calendarUI live) and handed down through AppDock, since
    /// each Tab owns its own NavigationStack and therefore its own bar.
    private var toolbarConfig: PhoneToolbarConfig {
        PhoneToolbarConfig(
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
    }

    var body: some View {
        ZStack {
            AppDock(
                selectedTab: $selectedTab,
                lunchState: lunchState,
                powerschoolState: powerschoolState,
                schoologyState: schoologyState,
                toolbarConfig: toolbarConfig,
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
                    withAnimation(.lsSpring) { showHomework = true }
                }
            )
            .environment(calendarUI)

            // Header is gone from this layer entirely — it's a real nav bar now,
            // applied per-tab inside AppDock (see PhoneToolbar). The top gradient
            // that used to fade content out behind the floating pill went with it;
            // the nav bar's own scroll-edge material does that job natively.
            // What remains here is only the pre-26 homework FAB, which has no
            // system equivalent below iOS 26 (26+ uses tabViewBottomAccessory).
            if #unavailable(iOS 26) {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Spacer()
                        HomeworkFAB {
                            withAnimation(.lsSpring) { showHomework = true }
                        }
                    }
                    .padding(.trailing, LS.md)
                    .padding(.bottom, LS.xxl)
                }
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
        .background(Color.lsBackground)
    }
}
