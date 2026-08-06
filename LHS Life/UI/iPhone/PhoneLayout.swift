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
    @Binding var showContacts: Bool
    let isLaunching: Bool
    let launchProgress: Double
    let calendarUI: CalendarUIState
    let lunchState: EmbeddedWebState
    let powerschoolState: EmbeddedWebState
    let schoologyState: EmbeddedWebState

    /// Incremented when the already-selected Map tab is tapped again.
    /// MapTabView watches the value, not a Bool, so two taps in a row both
    /// register — same edge-triggered idiom as CalendarUIState.scrollToNow.
    @State private var mapResetToken = 0
    
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
            onPhone: { showContacts = true },
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
                mapResetToken: mapResetToken,
                onSameTabTap: { tab in
                    switch tab {
                    case .events:      calendarUI.goToToday()
                    case .powerschool: powerschoolState.reload()
                    case .schoology:   schoologyState.reload()
                    case .lunch:       lunchState.reload()
                    case .map:         mapResetToken += 1
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
            //
            // The pre-26 homework FAB also used to live here, behind an
            // #unavailable check. It now lives inside LegacyTabDock, on the same
            // HStack row as the dock — that's the only way to guarantee the two
            // stay aligned, and it restores this file's stated invariant that
            // PhoneLayout has zero knowledge of which iOS version is running.
            
            if showHomework {
                HomeworkPopup(onDismiss: { withAnimation(.lsSpring) { showHomework = false } })
                    .environment(store)
                    .environment(settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
            
            if isLaunching {
                // Timing lives on the transition, not on the state write in
                // AppTabContainer — scoping it here means only this overlay
                // fades; the UI underneath is simply correct on the next
                // frame instead of animating into place.
                LaunchScreen(progress: launchProgress)
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                    .zIndex(20)
            }
        }
        .background(Color.lsBackground)
        .sheet(isPresented: $showContacts) {
            PhoneContactsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
