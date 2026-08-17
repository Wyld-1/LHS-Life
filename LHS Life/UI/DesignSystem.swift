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
    static let lsRose           = Color(light: "#B8368A", dark: "#F472B6")  // Visual & Performing Arts
    static let lsTeal           = Color(light: "#0E8C7A", dark: "#2DD4BF")  // Counseling/Guidance

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
    static let contentTopInset: CGFloat = 110

    // Tab bar
    static let tabBarHeight: CGFloat = 56

    // Legacy (pre-iOS 26) iPhone dock. Shared by PhoneTabDock and
    // HomeworkFAB — the two sit on one row and must resolve to the same
    // height, so the number lives here rather than being typed twice.
    static let dockHeight: CGFloat = 64

    // Floating-surface shadow (legacy dock, homework FABs). Deliberately
    // shallow: these sit on a light #F2F3F7 canvas where a 0.4-opacity
    // 24pt shadow reads as a smudge, not elevation.
    static let shadowOpacity: Double  = 0.12
    static let shadowRadius:  CGFloat = 10
    static let shadowY:       CGFloat = 3

    // Chromatic shadow — a floating surface casts in its OWN hue, not
    // neutral black. This is the core of the depth pass: a blue FAB over a
    // near-black canvas casting a gray shadow reads as a sticker; casting a
    // faint blue one reads as an object with light behind it.
    //
    // 0.18 is deliberate. The original code used 0.4, which bloomed into a
    // visible halo; pure black reads dead. 0.18 is felt, not seen.
    static let tintShadowOpacity: Double  = 0.18
    static let tintShadowRadius:  CGFloat = 12
    static let tintShadowY:       CGFloat = 4

    // Card surface treatment. The hairline is what stops a card from
    // dissolving into the canvas when the fill difference is only a few
    // percent — it's doing more work here than the shadow is.
    static let hairlineOpacity: Double  = 0.08
    static let hairlineWidth:   CGFloat = 0.5

    // Colored content blocks (period + event blocks in the day grid).
    //
    // The ramp is a constant RATE, not a per-block range. A block always
    // starts at blockFillTop and falls toward blockFillBottom at a fixed
    // rate per point of height, reaching bottom only at
    // blockGradientReference. So a 50-minute period travels ~30% of the
    // range and reads nearly solid, while a 3-hour event gets the full
    // sweep. Previously every block spanned the whole range regardless of
    // size — which is why one long event looked great and a column of
    // seven periods read as chaotic.
    static let blockFillTop:    Double = 0.24
    static let blockFillBottom: Double = 0.16
    static let blockStroke:     Double = 0.30

    /// Height at which a block shows the full gradient range. ~2.7 hours.
    static let blockGradientReference: CGFloat = 180

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
            .background {
                // Vertical gradient rather than a flat fill. The delta is
                // small on purpose — enough to imply a light source above,
                // not enough to read as a gradient.
                LinearGradient(
                    colors: elevated
                        ? [Color.lsSurfaceRaised, Color.lsSurface]
                        : [Color.lsSurface, Color.lsSurface.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous))
    }
}

/// Chromatic drop shadow tinted by the content's own color.
struct LSTintShadow: ViewModifier {
    let tint: Color
    var opacity: Double = LS.tintShadowOpacity
    func body(content: Content) -> some View {
        content.shadow(
            color: tint.opacity(opacity),
            radius: LS.tintShadowRadius,
            y: LS.tintShadowY
        )
    }
}

/// Gradient fill, plus an optional same-hue hairline, for colored content
/// blocks. Replaces flat `color.opacity(0.3)` fills, which desaturate to mud
/// on a near-black canvas — a red period block at 30% over #0A0C10 reads
/// brown.
struct LSBlockSurface: ViewModifier {
    let color: Color
    var cornerRadius: CGFloat = 5
    /// Block height in points. Supplied, the gradient runs at a constant
    /// rate so short blocks read nearly solid and only tall ones sweep the
    /// full range. Omitted, it spans the whole range regardless of size.
    var blockHeight: CGFloat? = nil
    var showsStroke: Bool = true

    private var bottomOpacity: Double {
        guard let blockHeight else { return LS.blockFillBottom }
        let travel = min(1, Double(blockHeight) / Double(LS.blockGradientReference))
        return LS.blockFillTop - (LS.blockFillTop - LS.blockFillBottom) * travel
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(LS.blockFillTop),
                                color.opacity(bottomOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        if showsStroke {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(color.opacity(LS.blockStroke), lineWidth: 0.5)
                        }
                    }
            }
    }
}

/// Inverse of the sphere treatment — dark rim above, light below, so the
/// shape reads as pressed into the surface rather than sitting on it.
/// Used for day chips in the week strip and month grid, where a raised
/// treatment would compete with the event blocks that genuinely float.
///
/// Toned back from 0.32/0.10 — at that strength the rim read as a drawn
/// outline rather than as shading, and a grid of 35 of them turned into
/// visible ornament. Still present, just no longer the loudest thing in
/// the cell.
struct LSRecessedCircle: ViewModifier {
    var strength: Double = 1.0
    func body(content: Content) -> some View {
        content.overlay {
            Circle().strokeBorder(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20 * strength),
                        Color.white.opacity(0.06 * strength)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
    }
}

// MARK: - Section chrome
//
// Shared by every sectioned surface (SettingsSheetView, PhoneContactsSheet,
// and anything added later). These lived duplicated in both sheets, which is
// exactly how two surfaces drift apart — one source of truth instead.

enum LSDivider {
    /// Rule separating whole SECTIONS. Deliberately brighter than `row`.
    static let sectionOpacity: Double = 0.40
    /// Hairline separating rows WITHIN one card.
    static let rowOpacity: Double = 0.15
    static let thickness: CGFloat = 0.5
}

/// Hairline between rows inside a card.
///
/// A Rectangle rather than `Divider()`: Divider draws its own separator in a
/// system color, and `.background(_:)` only tints the space BEHIND that line
/// — so the old `Divider().background(lsTertiary.opacity(0.3))` idiom was
/// rendering the system separator at full strength no matter what opacity it
/// was handed. This actually controls the line.
struct LSRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.lsTertiary.opacity(LSDivider.rowOpacity))
            .frame(height: LSDivider.thickness)
    }
}

/// Full-bleed rule marking a section break.
///
/// `inset` is the horizontal padding of the container this sits inside; it's
/// cancelled with negative padding so the rule runs bezel to bezel while the
/// content around it stays inset.
struct LSSectionDivider: View {
    var inset: CGFloat = LS.md
    var body: some View {
        Rectangle()
            .fill(Color.lsTertiary.opacity(LSDivider.sectionOpacity))
            .frame(height: LSDivider.thickness)
            .padding(.horizontal, -inset)
    }
}

/// Section header: letterspaced caps label, then a full-bleed rule closing it
/// off from the card beneath. The standard sectioned-list header for the app.
struct LSSectionLabel: View {
    let text: String
    var showsDivider: Bool = true
    var inset: CGFloat = LS.md

    var body: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            Text(text.uppercased())
                .font(.lsLabel)
                .foregroundStyle(Color.lsSecondary)
                .tracking(1)
                .padding(.leading, LS.xs)
            if showsDivider {
                LSSectionDivider(inset: inset)
            }
        }
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
    /// Drop shadow in the content's own hue — see LSTintShadow.
    func lsTintShadow(_ tint: Color, opacity: Double = LS.tintShadowOpacity) -> some View {
        modifier(LSTintShadow(tint: tint, opacity: opacity))
    }
    /// Gradient + optional hairline surface for colored blocks — see
    /// LSBlockSurface. Pass `height` for the constant-rate ramp.
    func lsBlockSurface(
        _ color: Color,
        cornerRadius: CGFloat = 5,
        height: CGFloat? = nil,
        stroke: Bool = true
    ) -> some View {
        modifier(LSBlockSurface(
            color: color,
            cornerRadius: cornerRadius,
            blockHeight: height,
            showsStroke: stroke
        ))
    }
    /// Pressed-in rim for circular chips — see LSRecessedCircle.
    func lsRecessedCircle(strength: Double = 1.0) -> some View {
        modifier(LSRecessedCircle(strength: strength))
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
