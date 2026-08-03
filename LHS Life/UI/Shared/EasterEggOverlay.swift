//
//  EasterEggOverlay.swift
//  LHS Life
//
//  Full-screen easter egg overlay. Hold "No school today" for 5 seconds.
//  Screen dims, quote fades in centered in gold italic.
//
//  Tap the quote → next quote
//  Tap background → dismiss
//

import SwiftUI

struct EasterEggOverlay: View {

    private var egg: EasterEggState { EasterEggState.shared }

    // ── Tuning ───────────────────────────────────────────────────────────────
    /// Background dim level. 0 = invisible, 1 = fully black.
    private let dimOpacity: Double = 0.80
    // ─────────────────────────────────────────────────────────────────────────

    var body: some View {
        if egg.isVisible {
            ZStack {
                // Dim layer — tap outside quote to dismiss
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                // Quote — fades in, tapping advances to next
                Text(egg.currentQuote)
                    .font(.lsTitle)
                    .italic()
                    .foregroundStyle(Color.lsGold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .id(egg.quoteToken)
                    .transition(.opacity)
                    .onTapGesture(count: 1) { advance() }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: egg.isVisible)
            .animation(.easeInOut(duration: 0.25), value: egg.quoteToken)
        }
    }

    private func advance() {
        HapticEngine.shared.bump()
        egg.nextQuote()
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            egg.isVisible = false
        }
    }
}

#Preview {
    ZStack {
        Color.lsBackground.ignoresSafeArea()
        Text("App content behind").foregroundStyle(.white)
        EasterEggOverlay()
    }
    .onAppear {
        EasterEggState.shared.nextQuote()
        EasterEggState.shared.isVisible = true
    }
}
