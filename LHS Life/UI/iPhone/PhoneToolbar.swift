//
//  PhoneToolbar.swift
//  LHS Life
//
//  iPhone-only. Replaces PhoneHeaderRow's floating ZStack overlay with a
//  real UINavigationBar toolbar, mirroring the pattern iPadRootView already
//  uses (principal/trailing items, ButtonSpec-shaped contextual button).
//
//  WHY THIS EXISTS — the floating header was a sibling of the tab content in
//  a ZStack, so its 124pt height was invisible to that content's layout. The
//  only way to account for it was LS.contentTopInset: a hardcoded duplicate
//  of a height SwiftUI already knew, hand-maintained inside the web views via
//  contentInset + repeated contentOffset corrections. A NavigationStack's nav
//  bar produces a REAL top safe-area inset instead, owned by the system, so
//  the duplicate (and every correction site that kept it in sync) goes away.
//
//  Applied per-tab inside PhoneTabDock, since each Tab gets its own
//  NavigationStack and therefore its own bar.
//

import SwiftUI

// MARK: - Config

/// The header's actions and state, lifted out of PhoneHeaderRow's parameter
/// list unchanged. Passed down from PhoneLayout through AppDock so each tab's
/// NavigationStack can build an identical bar.
struct PhoneToolbarConfig {
    var cycleLabel: String? = nil
    var onCycle: () -> Void = {}
    var canGoBack: Bool = false
    var onBack: () -> Void = {}
    var showSettingsBadge: Bool = false
    var onSettings: () -> Void = {}
    var onPhone: () -> Void = {}
    var onPillTap: () -> Void = {}
    var onEventTap: (SchoolEvent) -> Void = { _ in }
}

// MARK: - Toolbar Modifier

struct PhoneToolbar: ViewModifier {
    let tab: AppTab
    let config: PhoneToolbarConfig

    /// Same per-tab contextual button as before: cycle in Events, back in the
    /// web tabs, none in Lunch.
    private var contextualSymbol: String? {
        switch tab {
        case .events:                  return zoomSystemIcon(for: config.cycleLabel)
        case .powerschool, .schoology: return "chevron.left"
        default:                       return nil
        }
    }

    private var contextualEnabled: Bool {
        switch tab {
        case .powerschool, .schoology: return config.canGoBack
        default:                       return true
        }
    }

    private var contextualAction: () -> Void {
        switch tab {
        case .events:                  return config.onCycle
        case .powerschool, .schoology: return config.onBack
        default:                       return {}
        }
    }

    func body(content: Content) -> some View {
        content
            // No .navigationTitle — the principal item IS the title here.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // suppressGlass: the bar already provides the surface.
                    // Wrapping a self-glassing view in a toolbar item
                    // double-applies the material — the exact trap
                    // iPadRootView's ToolbarCapsule comment documents.
                    ScheduleHeaderPill(
                        onPillTap: config.onPillTap,
                        onEventTap: config.onEventTap,
                        suppressGlass: true
                    )
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let contextualSymbol {
                        Button {
                            contextualAction()
                        } label: {
                            Image(systemName: contextualSymbol)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.lsPrimary)
                        }
                        .tint(Color.lsPrimary)
                        .disabled(!contextualEnabled)
                        .opacity(contextualEnabled ? 1 : 0.35)
                    }
                }
                // ToolbarSpacer is the iOS 26 API that actually forces two
                // separate glass capsules. Two ToolbarItemGroups with the
                // same placement are merged by the system without this.
                if #available(iOS 26, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        config.onPhone()
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.lsPrimary)
                    }
                    Button {
                        config.onSettings()
                    } label: {
                        // Badge drawn as an overlay rather than .badge() —
                        // toolbar items don't carry a native badge affordance,
                        // and this matches the dot ToolbarCapsule drew before.
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.lsBlue)
                            .overlay(alignment: .topTrailing) {
                                if config.showSettingsBadge {
                                    Circle()
                                        .fill(Color.lsDestructive)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 3, y: -2)
                                }
                            }
                    }
                    .tint(Color.lsBlue)
                }
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

extension View {
    /// Wraps the view in its own NavigationStack and applies the shared
    /// iPhone bar. Each tab needs its own stack — a single stack around the
    /// TabView would give one bar for all tabs and lose per-tab context.
    func phoneToolbar(tab: AppTab, config: PhoneToolbarConfig) -> some View {
        NavigationStack {
            self.modifier(PhoneToolbar(tab: tab, config: config))
        }
    }
}
