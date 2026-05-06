//
//  DesignSystem.swift
//  LaSalle Schedule
//
//  Single source of truth for all visual constants: colors, typography,
//  spacing, corner radii, and animation curves.
//  Import this in every view file.
//

import SwiftUI

// MARK: - Colors

extension Color {
    // Backgrounds
    static let lsBackground     = Color(hex: "#0A0C10")  // Near-black base
    static let lsSurface        = Color(hex: "#13161C")  // Card / sheet background
    static let lsSurfaceRaised  = Color(hex: "#1C2029")  // Elevated card

    // LaSalle brand
    static let lsBlue           = Color(hex: "#3A6FD8")  // Royal blue (lightened for dark)
    static let lsGold           = Color(hex: "#F5B800")  // LaSalle gold

    // Text
    static let lsPrimary        = Color.white
    static let lsSecondary      = Color(hex: "#8A93A8")
    static let lsTertiary       = Color(hex: "#4A5168")

    // Semantic
    static let lsDestructive    = Color(hex: "#FF6B6B")
    static let lsSuccess        = Color(hex: "#34C78A")
    static let lsOrange         = Color(hex: "#FB923C")

    // Header gradient stops
    static let lsHeaderTop      = Color(hex: "#0D1220")
    static let lsHeaderBottom   = Color(hex: "#0A0C10")

    // MARK: Palette color → SwiftUI Color
    static func paletteColor(at index: Int) -> Color {
        Color(hex: ColorPalette.color(at: index).hex)
    }

    static func paletteColor(for config: PeriodConfig) -> Color {
        Color(hex: ColorPalette.color(at: config.colorIndex).hex)
    }

    // MARK: Hex init
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Typography

extension Font {
    // Display — large headers, time remaining
    static let lsDisplay     = Font.system(size: 34, weight: .bold,   design: .rounded)
    static let lsTitle       = Font.system(size: 22, weight: .bold,   design: .rounded)
    static let lsHeadline    = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let lsBody        = Font.system(size: 15, weight: .regular, design: .rounded)
    static let lsCaption     = Font.system(size: 12, weight: .medium,  design: .rounded)
    static let lsLabel       = Font.system(size: 11, weight: .semibold, design: .rounded)

    // Monospaced for times
    static let lsTime        = Font.system(size: 15, weight: .semibold, design: .monospaced)
    static let lsTimeLarge   = Font.system(size: 28, weight: .bold,    design: .monospaced)
}

// MARK: - Spacing

enum LS {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 16
    static let lg:   CGFloat = 24
    static let xl:   CGFloat = 32
    static let xxl:  CGFloat = 48

    // Corner radii
    static let radiusSm:  CGFloat = 8
    static let radiusMd:  CGFloat = 14
    static let radiusLg:  CGFloat = 20
    static let radiusXl:  CGFloat = 28

    // Header height (includes safe area padding)
    static let headerHeight: CGFloat = 88

    // Tab bar
    static let tabBarHeight: CGFloat = 56
}

// MARK: - Animation

extension Animation {
    static let lsSpring  = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let lsSnappy  = Animation.spring(response: 0.28, dampingFraction: 0.85)
    static let lsFade    = Animation.easeInOut(duration: 0.18)
}

// MARK: - View Modifiers

struct LSCard: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Color.lsSurfaceRaised : Color.lsSurface)
            .clipShape(RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous))
    }
}

struct LSPressEffect: ViewModifier {
    @State private var pressed = false
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.lsSnappy, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded   { _ in pressed = false; action() }
            )
    }
}

extension View {
    func lsCard(elevated: Bool = false) -> some View {
        modifier(LSCard(elevated: elevated))
    }
    func lsPressEffect(action: @escaping () -> Void) -> some View {
        modifier(LSPressEffect(action: action))
    }
}
