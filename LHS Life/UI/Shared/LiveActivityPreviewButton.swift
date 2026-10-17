//
//  LiveActivityPreviewButton.swift
//  LHS Life
//
//  "Preview Live Activities" — puts up a frozen sample Live Activity, because
//  most students don't know what one is until they see it. A row in
//  Settings → Lock Screen; the "couldn't start" sheet and the first
//  server-full alert call LiveActivityService.startPreview directly.
//
//  Hidden while a real Live Activity is running (it's already on the Lock
//  Screen) and on a Mac, which has no Lock Screen.
//

import SwiftUI

struct LiveActivityPreviewButton: View {
    @State private var service = LiveActivityService.shared

    static var isAvailable: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac && !LiveActivityService.shared.isRunning
    }

    var body: some View {
        if Self.isAvailable || service.isPreviewRunning {
            let running = service.isPreviewRunning
            Button {
                HapticEngine.shared.tick()
                if running {
                    Task { await service.endPreview() }
                } else {
                    service.startPreview()
                }
            } label: {
                // Concrete colors: inside a Button, .primary resolves to the
                // blue tint.
                Text(running ? "End Preview" : "Preview Live Activities")
                    .foregroundStyle(running ? Color.lsDestructive : Color.primary)
            }
        }
    }

    /// Where to look once it's up, or why it didn't start.
    static var hint: String? {
        let service = LiveActivityService.shared
        if let failure = service.previewFailure { return failure }
        guard service.isPreviewRunning else { return nil }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "Lock your \(device) to see it."
    }
}

/// The white symbol on a colored rounded square that Settings rows lead with.
struct SettingsRowIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
