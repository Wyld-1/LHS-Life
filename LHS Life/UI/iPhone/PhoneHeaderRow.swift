//
//  PhoneHeaderRow.swift
//  LHS Life
//
//  iPhone-only. Header pill leading and greedy; trailing ToolbarCapsule
//  holds an optional per-tab contextual button (cycle in Events, back in
//  the web tabs, none in Lunch) plus settings — one shared capsule, like
//  Calendar/Notes, not two separate circles. With no contextual button the
//  capsule naturally narrows to just settings.
//

import SwiftUI

struct PhoneHeaderRow: View {
    let selectedTab: AppTab
    let cycleLabel: String?
    let onCycle: () -> Void
    let canGoBack: Bool
    let onBack: () -> Void
    let showSettingsBadge: Bool
    let onSettings: () -> Void
    var onPillTap: (() -> Void)? = nil
    var onEventTap: ((SchoolEvent) -> Void)? = nil

    private var contextualSymbol: String? {
        switch selectedTab {
        case .events:                  return zoomSystemIcon(for: cycleLabel)
        case .powerschool, .schoology: return "chevron.left"
        default:                       return nil
        }
    }

    private var contextualEnabled: Bool {
        switch selectedTab {
        case .powerschool, .schoology: return canGoBack
        default:                       return true
        }
    }

    private var contextualAction: () -> Void {
        switch selectedTab {
        case .events:                  return onCycle
        case .powerschool, .schoology: return onBack
        default:                       return {}
        }
    }

    private var trailingButtons: [ToolbarCapsule.ButtonSpec] {
        var specs: [ToolbarCapsule.ButtonSpec] = []
        if let contextualSymbol {
            specs.append(.init(
                systemName: contextualSymbol,
                enabled: contextualEnabled,
                action: contextualAction
            ))
        }
        specs.append(.init(
            systemName: "person.fill",
            tint: Color.lsBlue,
            showBadge: showSettingsBadge,
            action: onSettings
        ))
        return specs
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: LS.sm) {
                    headerRow
                }
            } else {
                headerRow
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: LS.sm) {
            ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                .frame(maxWidth: .infinity)
            ToolbarCapsule(buttons: trailingButtons)
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
