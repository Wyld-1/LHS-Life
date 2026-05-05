//
//  WebNavButtons.swift
//  LHS Life
//
//  Vertical home/back pill shown on PowerSchool and Schoology tabs.
//  iOS 26+: GlassEffectContainer with per-button glassEffect() for interactive
//            liquid glass that morphs the two buttons into one connected surface.
//  iOS 17–25: ultraThinMaterial capsule.
//
//  Icon foregroundStyle is left unset so it inherits from the environment
//  (white on dark, dark on light) — identical to how the system tab bar
//  renders unselected icons.
//

import SwiftUI
internal import WebKit

struct WebNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            GlassNavButtons(webState: webState, onHomeTap: onHomeTap)
        } else {
            LegacyNavButtons(webState: webState, onHomeTap: onHomeTap)
        }
    }
}

// MARK: - iOS 26: Interactive liquid glass

@available(iOS 26, *)
private struct GlassNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        // GlassEffectContainer merges adjacent glass shapes into one connected
        // liquid glass surface. spacing: 0 forces them to touch and fuse.
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                GlassNavButton(icon: "house.fill", action: onHomeTap)

                Divider()
                    .opacity(0.15)

                GlassNavButton(
                    icon: "chevron.left",
                    action: { webState.webView?.goBack() },
                    isEnabled: webState.canGoBack
                )
            }
            .glassEffect(in: .capsule)
        }
    }
}

@available(iOS 26, *)
private struct GlassNavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button {
            HapticEngine.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
    }
}

// MARK: - iOS 17–25: Frosted glass capsule

private struct LegacyNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            LegacyNavButton(icon: "house.fill", action: onHomeTap)
            LegacyNavButton(
                icon: "chevron.left",
                action: { webState.webView?.goBack() },
                isEnabled: webState.canGoBack
            )
        }
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}

private struct LegacyNavButton: View {
    let icon: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button {
            HapticEngine.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.lsSecondary)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
    }
}
