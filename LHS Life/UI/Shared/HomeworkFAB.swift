//
//  HomeworkFAB.swift
//  LHS Life
//
//  Persistent one-tap "add homework" floating button. Used by iPhone
//  legacy (pre-iOS 26, where tabViewBottomAccessory doesn't exist) and by
//  iPad (always — the detail pane has no accessory-bar equivalent, and
//  there's no bottom-bar collision risk to design around on iPad anyway).
//

import SwiftUI

struct HomeworkFAB: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(Color.lsBlue)
                        .shadow(color: Color.lsBlue.opacity(0.4), radius: 12, y: 4)
                }
        }
        .buttonStyle(.plain)
    }
}
