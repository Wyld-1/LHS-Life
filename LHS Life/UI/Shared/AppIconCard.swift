//
//  AppIconCard.swift
//  LHS Life
//
//  The seasonal-icon choice: a pair of icon tiles, shown once as a card that
//  slides up on the first open of the season, and kept in Settings after.
//
//  The seasonal icon is already on the Home Screen when this appears — the
//  update put it there. So the card isn't asking permission; it's saying
//  "this is new, and here's how to undo it", with the seasonal icon selected.
//

import SwiftUI

// MARK: - Tiles

struct AppIconPicker: View {
    @Binding var selection: AppIconChoice

    var body: some View {
        HStack(spacing: LS.lg) {
            if let season = AppIconService.season {
                tile(.seasonal, name: season.name, asset: season.previewAsset)
            }
            tile(.classic, name: "Classic", asset: AppIconService.classicPreviewAsset)
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ choice: AppIconChoice, name: String, asset: String) -> some View {
        let isSelected = selection == choice
        return Button {
            HapticEngine.shared.tick()
            withAnimation(.lsSnappy) { selection = choice }
        } label: {
            VStack(spacing: LS.sm) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(isSelected ? Color.lsBlue : .clear, lineWidth: 3)
                    }
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.lsPrimary : Color.lsSecondary)
            }
            .contentShape(Rectangle())
        }
        // .borderless, not .plain: in a List row (Settings), any other style
        // hands a tap ANYWHERE in the row to a button in it — tapping the
        // gap between the tiles switched the icon to Classic.
        .buttonStyle(.borderless)
        .accessibilityLabel("\(name) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - First-open card

struct AppIconIntroCard: View {
    let onDone: (AppIconChoice) -> Void
    @State private var selection = AppIconService.shared.current

    /// Someone who picked Classic last season is still on Classic. They get
    /// an offer, not an announcement that something already changed.
    private var title: String {
        let name = AppIconService.season?.name ?? ""
        return AppIconService.shared.current == .seasonal
            ? "LHS Life Dressed Up for \(name)"
            : "A \(name) Icon Is Here"
    }

    var body: some View {
        VStack(spacing: LS.md) {
            VStack(spacing: LS.xs) {
                Text(title)
                    .font(.lsHeadline)
                    .multilineTextAlignment(.center)
                Text("Pick the icon you'd like on your Home Screen. You can change it anytime in Settings.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.lsSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppIconPicker(selection: $selection)
                .padding(.vertical, LS.xs)

            Button {
                onDone(selection)
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.lsBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(LS.lg)
        .frame(maxWidth: 480)
        // A tray attached to the bottom edge, like a sheet: the background
        // runs under the home indicator, the buttons stay above it. A card
        // floating above the safe area left a strip of app showing beneath.
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color.lsSurface)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.25), radius: 24, y: -4)
        }
    }
}

/// Places the intro card over the whole app: a light scrim, the card sliding
/// up from the bottom. Tapping the scrim keeps whatever is selected now —
/// the seasonal icon, unless they already chose Classic.
struct AppIconIntroOverlay: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { finish(AppIconService.shared.current) }
                        .transition(.opacity)
                    AppIconIntroCard(onDone: finish)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.lsSpring, value: isPresented)
        }
    }

    private func finish(_ choice: AppIconChoice) {
        AppIconService.shared.markIntroduced()
        isPresented = false
        // After the card is gone, so iOS's "You have changed the icon" alert
        // doesn't land on top of a card that's still animating out.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            await AppIconService.shared.choose(choice)
        }
    }
}
