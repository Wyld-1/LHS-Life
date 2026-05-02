//
//  HapticEngine.swift
//  LHS Life
//
//  Centralizes all haptic feedback. Generators are created once and kept alive —
//  never instantiated at the call site. prepare() is called at app launch so the
//  Taptic Engine is warm and fires with zero latency on first interaction.
//
//  App target only.
//

import UIKit

@MainActor
final class HapticEngine {

    static let shared = HapticEngine()

    private let impact   = UIImpactFeedbackGenerator(style: .light)
    private let medium   = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    /// Call once at app launch — warms the Taptic Engine so first-use has no delay.
    func prepare() {
        impact.prepare()
        medium.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Call sites

    /// Light tap — button presses, toggles
    func tap() { impact.impactOccurred(); impact.prepare() }

    /// Medium tap — tab switches, confirmations
    func bump() { medium.impactOccurred(); medium.prepare() }

    /// Selection tick — color picker, period row editing
    func tick() { selection.selectionChanged(); selection.prepare() }

    /// Success — save, done
    func success() { notification.notificationOccurred(.success); notification.prepare() }
}
