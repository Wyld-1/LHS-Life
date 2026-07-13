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
    static let lsBackground     = Color(light: "#F2F3F7", dark: "#0A0C10")  // Page canvas
    static let lsSurface        = Color(light: "#FFFFFF", dark: "#13161C")  // Card / sheet background
    static let lsSurfaceRaised  = Color(light: "#F7F8FA", dark: "#1C2029")  // Elevated card

    // LaSalle brand
    static let lsBlue           = Color(light: "#2F5FC4", dark: "#3A6FD8")  // Royal blue (deepened for light-mode contrast on white)
    static let lsGold           = Color(light: "#A8790A", dark: "#F5B800")  // LaSalle gold (darkened — pure gold on white reads low-contrast)

    // Text
    static let lsPrimary        = Color(light: "#0A0C10", dark: "#FFFFFF")  // Flips: near-black on light, white on dark
    static let lsSecondary      = Color(light: "#5B6472", dark: "#8A93A8")
    static let lsTertiary       = Color(light: "#9AA1AF", dark: "#4A5168")

    // Semantic
    static let lsDestructive    = Color(light: "#D64545", dark: "#FF6B6B")
    static let lsSuccess        = Color(light: "#1F9968", dark: "#34C78A")
    static let lsOrange         = Color(light: "#C9691F", dark: "#FB923C")
    static let lsPurple         = Color(light: "#6425C4", dark: "#7C3AED")

    // Header gradient stops
    static let lsHeaderTop      = Color(light: "#FAFBFC", dark: "#0D1220")
    static let lsHeaderBottom   = Color(light: "#F2F3F7", dark: "#0A0C10")

    // MARK: Palette color → SwiftUI Color
    // NOTE: period/subject colors (ColorPalette) are a separate, user-chosen
    // palette (the color-picker grid in Settings) — not part of the light/
    // dark token system above. Not touched here; those are fixed brand-ish
    // accent swatches the user picks per-period, expected to read the same
    // regardless of appearance, same as how a label-maker's colors don't
    // change with the room lighting.
    static func paletteColor(at index: Int) -> Color {
        Color(hex: ColorPalette.color(at: index).hex)
    }

    static func paletteColor(for config: PeriodConfig) -> Color {
        Color(hex: ColorPalette.color(at: config.colorIndex).hex)
    }

    // MARK: Hex init (fixed, non-adaptive — same color in light and dark)
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    // MARK: Dynamic init — resolves differently per system appearance.
    // This is what actually makes a token "light-mode ready": the plain
    // hex init above always returns the same fixed color regardless of
    // system appearance; this one picks between two hex values based on
    // the active UITraitCollection at render time.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8)  & 0xFF) / 255
        let b = CGFloat(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
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

    // Universal top inset — distance from screen top to where content begins.
    static let contentTopInset: CGFloat = 124

    // Tab bar
    static let tabBarHeight: CGFloat = 56

    // Standard height for inline pill/chip controls (class selector,
    // priority selector, due date selector, Settings' Grad Year and Live
    // Activities chips). Explicit height rather than matching padding,
    // since these controls use different font sizes — matching padding
    // alone doesn't reliably produce matching visual height across them.
    static let chipHeight: CGFloat = 32
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
    /// Conditionally apply a modifier — avoids ternary type mismatch.
    @ViewBuilder
    func ifTrue<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
