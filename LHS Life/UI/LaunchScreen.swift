//
//  LaunchScreen.swift
//  LHS Life
//
//  Shown briefly while the calendar loads. Web views load in the background
//  and nothing waits on them — see AppTabContainer.launchProgress.
//
//  Stripped back to just the mark: no progress bar, no loading phrase. The
//  gate is a single fast condition now, so a bar had one input and read as a
//  flash, and a phrase nobody had time to read was decoration on a screen
//  whose whole job is to get out of the way.
//

import SwiftUI

struct LaunchScreen: View {
    /// Retained so the call sites in PhoneLayout and iPadRootView don't have
    /// to change, and so a determinate bar can come back if the launch gate
    /// ever grows more than one input again. Currently unused.
    let progress: Double  // 0.0 → 1.0

    var body: some View {
        VStack(spacing: LS.sm) {
            Spacer()

            // Logo / wordmark. LaunchScreen.storyboard places the system
            // launch logo at this exact size and position — keep them in sync.
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
        }
        .padding(.bottom, LS.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lsBackground.ignoresSafeArea())
        // Campus photo, commented out rather than deleted — the layout note
        // below is the expensive part to rediscover, not the four lines.
        //
        // It must stay a BACKGROUND, never a ZStack sibling. As a sibling it
        // drove layout: .scaledToFill() lets the image grow past its
        // container to preserve aspect ratio, and a ZStack sizes itself to
        // its largest child — so on a wide Mac window the stack became taller
        // than the window and the content laid out against that oversized
        // frame, pushing the bottom of the VStack off screen. iPhone and iPad
        // never showed it because their aspect ratios are close enough to the
        // photo's that the overflow stayed small.
        //
        // .background {
        //     Image("campus")
        //         .resizable()
        //         .scaledToFill()
        //         .overlay { Color.lsBackground.opacity(0.85) }
        //         .clipped()
        //         .ignoresSafeArea()
        // }
    }
}

#Preview {
    LaunchScreen(progress: 0.6)
}
