//
//  WebNavButtons.swift
//  LHS Life
//
//  Vertical home/back pill shown on PowerSchool and Schoology tabs.
//  iOS 26+: liquid glass background via glassEffect()
//  iOS 17–25: ultraThinMaterial capsule
//

import SwiftUI
internal import WebKit

struct WebNavButtons: View {
    @Bindable var webState: EmbeddedWebState
    let onHomeTap: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            WebNavButton(icon: "house.fill", action: onHomeTap)

            WebNavButton(icon: "chevron.left") {
                webState.webView?.goBack()
                HapticEngine.shared.tap()
            }
            .opacity(webState.canGoBack ? 1 : 0.35)
            .disabled(!webState.canGoBack)
        }
        .background {
            if #available(iOS 26, *) {
                Capsule()
                    .glassEffect()
            } else {
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
}

private struct WebNavButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }
}
