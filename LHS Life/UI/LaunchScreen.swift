//
//  LaunchScreen.swift
//  LHS Life
//
//  Shown on first launch while web views and calendar data are loading.
//  Automatically dismisses once all three web states are ready.
//  Blocks interaction — the app is genuinely not ready until dismissed.
//

import SwiftUI

struct LaunchScreen: View {
    let progress: Double  // 0.0 → 1.0

    var body: some View {
        ZStack {
            Color.lsBackground.ignoresSafeArea()

            VStack(spacing: LS.xl) {
                Spacer()

                // Logo / wordmark
                VStack(spacing: LS.md) {
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 90, height: 90)

                    VStack(spacing: LS.sm) {
                        Text("LHS Life")
                            .font(.lsDisplay)
                            .foregroundStyle(Color.lsPrimary)
                        Text("LA SALLE HIGH SCHOOL · YAKIMA")
                            .font(.lsLabel)
                            .foregroundStyle(Color.lsSecondary)
                            .tracking(2)
                    }
                }

                Spacer()
                Spacer()

                // Progress bar
                VStack(spacing: LS.sm) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.lsTertiary.opacity(0.3))
                                .frame(height: 6)
                            Capsule()
                                .fill(Color.lsBlue)
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, LS.xxl)

                    Text("Loading…")
                        .font(.lsLabel)
                        .foregroundStyle(Color.lsSecondary)
                        .tracking(1)
                }
                .padding(.bottom, LS.xxl)
            }
        }
    }
}

#Preview {
    LaunchScreen(progress: 0.6)
}
