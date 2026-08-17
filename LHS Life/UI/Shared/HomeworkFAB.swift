//
//  HomeworkFAB.swift
//  LHS Life
//
//  Persistent one-tap "add homework" floating button. Used by iPhone
//  legacy (pre-iOS 26, where tabViewBottomAccessory doesn't exist).
//  iPad has its own larger variant (iPadHomeworkFAB in iPadRootView).
//
//  Sized to LS.dockHeight so it matches the legacy dock it sits beside —
//  the two are laid out in a single HStack in PhoneTabDock, so changing
//  that token moves both together.
//

import SwiftUI

struct HomeworkFAB: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: LS.dockHeight, height: LS.dockHeight)
                .background { Circle().fill(Color.lsBlue) }
                // Chromatic, not neutral. Earlier in this pass I replaced the
                // original blue shadow with black — right call on the amount
                // (0.4 bloomed), wrong on the hue. This is the corrected form.
                .lsTintShadow(Color.lsBlue)
        }
        .buttonStyle(.plain)
    }
}
