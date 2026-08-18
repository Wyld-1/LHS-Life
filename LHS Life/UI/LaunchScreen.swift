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

    /// Same idiom check AppTabContainer branches on for PhoneLayout vs
    /// iPadRootView — kept identical so the launch screen and the app it
    /// hands off to never disagree about which device they're on.
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Fixed per-platform bar width. 300 is tuned; 460 is a first pass.
    private var barWidth: CGFloat { isPhone ? 300 : 460 }

    var body: some View {
        VStack(spacing: LS.sm) {
            Spacer()

            // Logo / wordmark
            Image("lhs-lightning")
                .resizable()
                .renderingMode(.original)
                .frame(width: 90, height: 90)
                .padding(.vertical, LS.xs)

            Text("LHS Life")
                .font(.lsDisplay)
                .foregroundStyle(Color.lsPrimary)
            Text("LA SALLE HIGH SCHOOL · YAKIMA")
                .font(.lsLabel)
                .foregroundStyle(Color.lsSecondary)
                .tracking(2)

            Spacer()
            Spacer()

            // Progress bar
            Capsule()
                .fill(Color.lsTertiary.opacity(0.3))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.lsBlue)
                            .frame(width: geo.size.width * progress)
                    }
                    .animation(.easeInOut(duration: 0.3), value: progress)
                }
                .frame(maxWidth: barWidth)
                .padding(.horizontal, LS.xxl)

            Text("Loading…")
                .font(.lsLabel)
                .foregroundStyle(Color.lsSecondary)
                .tracking(1)
        }
        .padding(.bottom, LS.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The campus photo is a BACKGROUND, not a ZStack sibling.
        //
        // As a sibling it drove layout: .scaledToFill() lets the image grow
        // past its container to preserve aspect ratio, and a ZStack sizes
        // itself to its largest child — so on a wide Mac window the stack
        // became taller than the window, and the VStack laid out against that
        // oversized frame with the progress bar pushed off the bottom edge.
        // iPhone and iPad never showed it because their aspect ratios are
        // close enough to the photo's that the overflow stayed small.
        //
        // Background content is measured against the primary view and does
        // not affect its layout, so the overflow is now harmless and
        // .clipped() trims it.
        .background {
            Image("campus")
                .resizable()
                .scaledToFill()
                .overlay { Color.lsBackground.opacity(0.85) }
                .clipped()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    LaunchScreen(progress: 0.6)
}
