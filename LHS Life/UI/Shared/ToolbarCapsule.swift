//
//  ToolbarCapsule.swift
//  LHS Life
//
//  One shared toolbar-style capsule (Calendar/Notes pattern): a single
//  glassEffect(in: Capsule()) around plain icon buttons on iOS 26+, or one
//  shared frosted Capsule background pre-26 — never per-button circles.
//
//  Generalized over HeaderTrailingCapsule: takes a list of button specs
//  instead of assuming "contextual button + settings". iPhone's
//  PhoneHeaderRow passes 1-2 buttons (contextual + settings); iPad's detail
//  toolbar passes just 1 (contextual only, since settings lives in the
//  sidebar there). With one button the capsule naturally narrows to a
//  single circle — no special-casing needed.
//

import SwiftUI

struct ToolbarCapsule: View {

    struct ButtonSpec: Identifiable {
        let id = UUID()
        let systemName: String
        var tint: Color = Color.lsPrimary
        var enabled: Bool = true
        var showBadge: Bool = false
        let action: () -> Void
    }

    let buttons: [ButtonSpec]

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 20

    var body: some View {
        if #available(iOS 26, *) {
            toolbarContent
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            toolbarContent
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 6) {
            ForEach(buttons) { spec in
                iconButton(spec)
            }
        }
        .frame(height: buttonSize)
    }

    private func iconButton(_ spec: ButtonSpec) -> some View {
        Button {
            spec.action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: spec.systemName)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(spec.tint)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
                if spec.showBadge {
                    Circle()
                        .fill(Color.lsDestructive)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(spec.enabled ? 1 : 0.35)
        .disabled(!spec.enabled)
    }
}
