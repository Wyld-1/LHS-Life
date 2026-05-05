//
//  WebNavButtons.swift
//  LHS Life
//
//  iOS 26+: GlassEffectContainer fuses two .buttonStyle(.glass) buttons
//            into one connected liquid glass surface. Interactive bounce/shimmer
//            on tap is built into .buttonStyle(.glass) — no extra modifier needed.
//            Icons use .primary foregroundStyle so the glass system adapts their
//            luminance and contrast to whatever content is underneath.
//
//  iOS 17–18: ultraThinMaterial capsule, right-anchored, fixed width.
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

// MARK: - iOS 26+: Fused interactive glass

@available(iOS 26, *)
private struct GlassNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        // One glass capsule, two tappable regions inside.
        // .glassEffect(.regular.interactive()) on the outer shape gives
        // the whole capsule the bounce/shimmer response as one unit.
        VStack(spacing: 0) {
            Button {
                HapticEngine.shared.tap()
                onHomeTap()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Button {
                HapticEngine.shared.tap()
                webState.webView?.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .opacity(webState.canGoBack ? 1 : 0.35)
            .disabled(!webState.canGoBack)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - iOS 17–25: frosted capsule

private struct LegacyNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LegacyNavButton(icon: "house.fill", action: onHomeTap)

            Divider()
                .background(Color.lsTertiary.opacity(0.4))
                .frame(width: 28)

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
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.lsSecondary)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
    }
}
