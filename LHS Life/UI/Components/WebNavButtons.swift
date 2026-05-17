//
//  FloatingNavButtons.swift
//  LHS Life
//
//  A single floating capsule button group used across the app.
//  Callers declare a NavButtonsRole — the component handles icons,
//  actions, and enabled states. Glass rendering is role-agnostic.
//
//  iOS 26+: GlassEffectContainer fuses buttons into one liquid glass surface.
//  iOS 17–25: ultraThinMaterial frosted capsule.
//

import SwiftUI
internal import WebKit

// MARK: - Role

enum NavButtonsRole {
    /// Browser-style back + home buttons for embedded web views.
    case web(state: EmbeddedWebState, onHome: () -> Void)
    /// Calendar view mode controls: Today + zoom-out toggle.
    case calendar(onToday: () -> Void, isOnToday: Bool, zoomLabel: String?, onZoom: (() -> Void)?)
}

// MARK: - Button Descriptor
// Role-agnostic description of one button in the capsule.

private struct NavButtonItem: Identifiable {
    let id: String
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true
    var tint: Color? = nil
}

private func items(for role: NavButtonsRole) -> [NavButtonItem] {
    switch role {
    case .web(let state, let onHome):
        return [
            NavButtonItem(id: "home", icon: "house.fill", action: onHome),
            NavButtonItem(id: "back", icon: "chevron.left",
                          action: { state.webView?.goBack() },
                          isEnabled: state.canGoBack)
        ]
    case .calendar(let onToday, let isOnToday, let zoomLabel, let onZoom):
        var result = [NavButtonItem(id: "today", icon: "inset.filled.circle", action: onToday, tint: isOnToday ? Color.lsDestructive : nil)]
        if let onZoom, let zoomLabel {
            result.append(NavButtonItem(id: "zoom", icon: zoomIcon(for: zoomLabel), action: onZoom))
        }
        return result
    }
}

private func zoomIcon(for label: String) -> String {
    switch label {
    case "Month": return "square.grid.2x2.fill"
    case "Year":  return "square.grid.3x3.fill"
    case "Day":   return "calendar.day.timeline.leading"
    default:      return "calendar"
    }
}

// MARK: - Public entry point

struct FloatingNavButtons: View {
    let role: NavButtonsRole

    var body: some View {
        if #available(iOS 26, *) {
            GlassFloatingButtons(items: items(for: role))
        } else {
            LegacyFloatingButtons(items: items(for: role))
        }
    }
}

// Convenience alias so existing call sites need minimal changes.
typealias WebNavButtons = FloatingNavButtons

// MARK: - iOS 26+: Fused interactive glass

@available(iOS 26, *)
private struct GlassFloatingButtons: View {
    let items: [NavButtonItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    HapticEngine.shared.tap()
                    item.action()
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .opacity(item.isEnabled ? 1 : 0.35)
                .disabled(!item.isEnabled)
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - iOS 17–25: frosted capsule

private struct LegacyFloatingButtons: View {
    let items: [NavButtonItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                        .background(Color.lsTertiary.opacity(0.4))
                        .frame(width: 28)
                }
                Button {
                    HapticEngine.shared.tap()
                    item.action()
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.tint ?? Color.lsSecondary)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .opacity(item.isEnabled ? 1 : 0.35)
                .disabled(!item.isEnabled)
            }
        }
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}
