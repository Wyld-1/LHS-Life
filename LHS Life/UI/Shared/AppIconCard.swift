//
//  AppIconCard.swift
//  LHS Life
//
//  The holiday-icon choice: a row of icon tiles, shown once as a card that
//  slides up on the first open of a holiday window, and in Settings for the
//  rest of it (see AppIconService for the windows).
//
//  The card arrives with the holiday icon selected, and its button says what
//  it will do ("Use Halloween Icon"), so one tap dresses the app up and
//  nothing changes without the student asking.
//

import SwiftUI

// MARK: - Tiles

struct AppIconPicker: View {
    let options: [AppIconService.Icon]
    @Binding var selection: AppIconService.Icon

    var body: some View {
        HStack(spacing: LS.lg) {
            ForEach(options) { tile($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ icon: AppIconService.Icon) -> some View {
        let isSelected = selection == icon
        let name = icon.name
        return Button {
            HapticEngine.shared.tick()
            withAnimation(.lsSnappy) { selection = icon }
        } label: {
            VStack(spacing: LS.sm) {
                Image(icon.previewAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(LS.xs)
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
    let onDone: (AppIconService.Icon) -> Void

    private let service = AppIconService.shared
    private let holiday = AppIconService.activeHoliday()?.holiday.icon
    @State private var selection: AppIconService.Icon

    init(onDone: @escaping (AppIconService.Icon) -> Void) {
        self.onDone = onDone
        _selection = State(initialValue: AppIconService.activeHoliday()?.holiday.icon
                                        ?? AppIconService.shared.current)
    }

    private var title: String {
        guard let holiday else { return "App Icon" }
        return service.current == holiday
            ? "Dressed Up for \(holiday.name)"
            : "New \(holiday.name) Icon"
    }

    /// Says what the tap will do, so nothing changes by surprise.
    private var buttonTitle: String {
        selection == service.current ? "Done" : "Use \(selection.name) Icon"
    }

    var body: some View {
        VStack(spacing: LS.md) {
            VStack(spacing: LS.xs) {
                Text(title)
                    .font(.lsHeadline)
                    .multilineTextAlignment(.center)
                Text("Change anytime in Settings.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.lsSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppIconPicker(options: service.options, selection: $selection)
                .padding(.vertical, LS.xs)

            Button {
                onDone(selection)
            } label: {
                Text(buttonTitle)
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
/// up from the bottom. Tapping the scrim keeps the icon they have now.
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

    private func finish(_ choice: AppIconService.Icon) {
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
