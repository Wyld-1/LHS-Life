//
//  iPadRootView.swift
//  LHS Life
//
//  Ground-up iPad rebuild — replaces the old iPadTabView entirely.
//  NavigationSplitView (iOS 16+, no glass dependency for the structure
//  itself — only the toolbar button and pill glass touches are gated to
//  iOS 26+, same as everywhere else).
//
//  Sidebar: iPadSidebar (Today module, 4 nav rows, pinned Settings).
//  Detail:  the four tab content views, unchanged from iPhone/Tabs/.
//           Top toolbar holds only Button 1 (cycle in Events, back in the
//           web tabs, none in Lunch) as a PLAIN button — the system
//           toolbar already applies its own glass to ToolbarItem content
//           automatically, so wrapping it in ToolbarCapsule (which also
//           applies glassEffect) double-applies glass and breaks. Homework
//           FAB floats bottom-trailing regardless of selected tab.
//

import SwiftUI
internal import WebKit

struct iPadRootView: View {

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

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            NavigationSplitView(columnVisibility: $columnVisibility) {
                iPadSidebar(
                    selectedTab: $selectedTab,
                    onSameTabTap: { tab in
                        switch tab {
                        case .events:      calendarUI.goToToday()
                        case .powerschool: powerschoolState.reload()
                        case .schoology:   schoologyState.reload()
                        case .lunch:       lunchState.reload()
                        default: break
                        }
                    },
                    onSettingsTap: {
                        settings.apBadgeCleared = true
                        showSettings = true
                    },
                    showSettingsBadge: showBadge
                )
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)

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

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch selectedTab {
            case .events:
                EventsTabView()
                    .environment(calendarUI)
            case .lunch:
                LunchTabView(webState: lunchState)
            case .powerschool:
                PowerSchoolTabView(webState: powerschoolState)
            case .schoology:
                SchoologyTabView(webState: schoologyState)
            case .homework:
                EmptyView()
            }
        }
        .navigationTitle(selectedTab.title)
        .toolbar {
            if let button = contextualToolbarButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticEngine.shared.tap()
                        button.action()
                    } label: {
                        Image(systemName: button.systemName)
                            .font(.system(size: 17, weight: .regular))
                    }
                    .disabled(!button.enabled)
                    .opacity(button.enabled ? 1 : 0.35)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            iPadHomeworkFAB {
                HapticEngine.shared.bump()
                withAnimation(.lsSpring) { showHomework = true }
            }
            .padding(.trailing, LS.lg)
            .padding(.bottom, LS.lg)
            .ignoresSafeArea(edges: [.bottom, .trailing])
        }
    }

    /// Plain data holder — systemName/enabled/action only. No glass baked
    /// in here (that lived in ToolbarCapsule's rendering, not this spec),
    /// so it's safe to render as a native plain toolbar Button above.
    private var contextualToolbarButton: ToolbarCapsule.ButtonSpec? {
        switch selectedTab {
        case .events:
            return .init(
                systemName: zoomSystemIcon(for: calendarUI.zoomOutLabel),
                action: { calendarUI.zoomOutAction() }
            )
        case .powerschool:
            return .init(
                systemName: "chevron.left",
                enabled: powerschoolState.canGoBack,
                action: { powerschoolState.webView?.goBack() }
            )
        case .schoology:
            return .init(
                systemName: "chevron.left",
                enabled: schoologyState.canGoBack,
                action: { schoologyState.webView?.goBack() }
            )
        default:
            return nil
        }
    }

    private func zoomSystemIcon(for label: String?) -> String {
        switch label {
        case "Month": return "square.grid.2x2.fill"
        case "Year":  return "square.grid.3x3.fill"
        case "Day":   return "calendar.day.timeline.leading"
        default:      return "calendar"
        }
    }
}

// MARK: - iPad Homework FAB
// Bigger than iPhone's (this is the only add-homework affordance on iPad,
// so it carries more visual weight) and positioned to sit intentionally
// close to the true hardware corner rather than an arbitrary safe-area
// inset — ignoresSafeArea lets it resolve against the physical screen edge.
//
// NOTE on concentricity: iOS 26's ConcentricRectangle API matches ROUNDED
// RECTANGLE corner radii to their container's — it's not really a
// meaningful transform on a full Circle, which has no discrete corners to
// begin with (Apple's own Reminders "+" button is circular too, not a
// squircle). What actually achieves "sits in harmony with the bezel" for
// a circular button is precise, deliberate positioning relative to the
// true corner, which is what this does. If you want literal
// ConcentricRectangle corner-matching, that argues for a rounded-square
// FAB instead of a circle — happy to try that if you'd rather.
private struct iPadHomeworkFAB: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(Color.lsBlue)
                        .shadow(color: Color.lsBlue.opacity(0.4), radius: 14, y: 4)
                }
        }
        .buttonStyle(.plain)
    }
}
