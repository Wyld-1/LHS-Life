//
//  LSConfirmationOverlay.swift
//  LHS Life
//
//  Transient success confirmation — a centered squircle with a drawn-on
//  glyph and a caption, auto-dismissing after a beat. Mimics the Face ID
//  success card.
//
//  There is NO public Apple API for this. The system HUD (volume, AirPods,
//  Silent Mode) is private UIKit and not shippable, so every app showing one
//  builds it. The documented pieces used here are the glass/material
//  backing, .symbolEffect(.drawOn) (SF Symbols 7, iOS 26+), and
//  UINotificationFeedbackGenerator via HapticEngine.success().
//
//  Structure deliberately mirrors EasterEggOverlay: an @Observable singleton
//  holds the state, a thin View renders it, and the host places one instance
//  at the top of its ZStack.
//

import SwiftUI

// MARK: - State

@MainActor
@Observable
final class ConfirmationState {

    /// Success vs. failure. Drives glyph tint and haptic together so the two
    /// can't disagree — a success chime under a warning triangle would read
    /// as a bug.
    enum Style {
        case success
        case warning

        var defaultSymbol: String {
            switch self {
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .lsSuccess
            case .warning: return .lsGold
            }
        }

        @MainActor
        func playHaptic() {
            switch self {
            case .success: HapticEngine.shared.success()
            case .warning: HapticEngine.shared.error()
            }
        }
    }

    static let shared = ConfirmationState()
    private init() {}

    private(set) var isVisible = false
    private(set) var message = ""
    private(set) var symbolName = "checkmark.circle"
    private(set) var style: Style = .success

    /// Flipped a beat AFTER the card appears so .drawOn has a false → true
    /// edge to animate against. Without the delay the symbol is already
    /// drawn by the time the card fades in and the effect never plays.
    private(set) var symbolDrawn = false

    private var dismissTask: Task<Void, Never>?

    /// Shows the confirmation. Safe to call repeatedly — a second call
    /// restarts the timer rather than stacking overlays.
    ///
    /// `symbol` defaults to the style's glyph; pass one only to override.
    /// Warnings linger longer because they carry a reason worth reading.
    func show(
        _ message: String,
        style: Style = .success,
        symbol: String? = nil,
        duration: TimeInterval? = nil
    ) {
        dismissTask?.cancel()

        self.message = message
        self.style = style
        self.symbolName = symbol ?? style.defaultSymbol
        self.symbolDrawn = false

        let visibleFor = duration ?? (style == .warning ? 2.8 : 1.8)

        withAnimation(.lsSpring) { isVisible = true }
        style.playHaptic()

        dismissTask = Task { @MainActor in
            // Let the card land before the glyph starts drawing — Face ID
            // does the same: the card settles, then the checkmark strokes.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            symbolDrawn = true

            try? await Task.sleep(nanoseconds: UInt64(visibleFor * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) { isVisible = false }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.28)) { isVisible = false }
    }
}

// MARK: - View

struct LSConfirmationOverlay: View {

    private var state: ConfirmationState { ConfirmationState.shared }

    // ── Tuning ───────────────────────────────────────────────────────────────
    private let cardSize:  CGFloat = 172
    private let glyphSize: CGFloat = 76
    // ─────────────────────────────────────────────────────────────────────────

    var body: some View {
        if state.isVisible {
            VStack(spacing: LS.md) {
                glyph
                Text(state.message)
                    .font(.lsHeadline)
                    .foregroundStyle(Color.lsPrimary)
                    .multilineTextAlignment(.center)
                    // Failure captions carry a reason and need the room;
                    // three lines fits "Turn on Live Activities in iPhone
                    // Settings" without shrinking the type to nothing.
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, LS.md)
            }
            .frame(width: cardSize, height: cardSize)
            .background { cardBackground }
            // Settles rather than springing in from nothing — matching the
            // Face ID card, which scales from just under full size.
            .transition(.opacity.combined(with: .scale(scale: 0.88)))
            // Non-interactive: this is a status report, not a control, and
            // must never eat a tap meant for the UI underneath.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(state.message)
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private var glyph: some View {
        Group {
            if #available(iOS 26, *) {
                // .drawOn strokes the symbol like handwriting — the closest
                // documented equivalent to the Face ID checkmark.
                // wholeSymbol draws all layers in one movement; byLayer
                // staggers them, which reads as hesitant at this size.
                Image(systemName: state.symbolName)
                    .font(.system(size: glyphSize, weight: .regular))
                    .symbolEffect(.drawOn.wholeSymbol, isActive: state.symbolDrawn)
            } else {
                // Pre-26 fallback: bounce is the nearest documented effect.
                Image(systemName: state.symbolName)
                    .font(.system(size: glyphSize, weight: .regular))
                    .symbolEffect(.bounce, value: state.symbolDrawn)
            }
        }
        .foregroundStyle(state.style.tint)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: LS.radiusXl, style: .continuous)
        if #available(iOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(LS.shadowOpacity),
                        radius: LS.shadowRadius, y: LS.shadowY)
        } else {
            shape
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(LS.shadowOpacity),
                        radius: LS.shadowRadius, y: LS.shadowY)
        }
    }
}

#Preview {
    ZStack {
        Color.lsBackground.ignoresSafeArea()
        Text("App content behind").foregroundStyle(Color.lsPrimary)
        LSConfirmationOverlay()
    }
    .onAppear {
        ConfirmationState.shared.show("Live Activities started")
    }
}
