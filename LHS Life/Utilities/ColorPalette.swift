//
//  ColorPalette.swift
//  LHS Life
//
//  10 colors ordered by the rainbow (ROYGBIV + extras).
//  Default period assignments: gray, red, orange, yellow, sky, blue, green, lavender, gray
//
//  Add this file to: LHS Life target + LHS Widgets target
//

import Foundation

enum ColorPalette {

    struct PaletteColor: Identifiable, Codable, Hashable {
        let id: Int
        let name: String
        let hex: String
    }

    /// Rainbow-ordered palette.
    static let colors: [PaletteColor] = [
        PaletteColor(id: 0, name: "Slate",     hex: "#94A3B8"),  // Gray
        PaletteColor(id: 1, name: "Coral",     hex: "#FF6B6B"),  // Red
        PaletteColor(id: 2, name: "Peach",     hex: "#FB923C"),  // Orange
        PaletteColor(id: 3, name: "Gold",      hex: "#F5B800"),  // Yellow
        PaletteColor(id: 4, name: "Mint",      hex: "#34C78A"),  // Green
        PaletteColor(id: 5, name: "Sky",       hex: "#38BDF8"),  // Light blue
        PaletteColor(id: 6, name: "LaSalle",   hex: "#3A6FD8"),  // Dark blue
        PaletteColor(id: 7, name: "Lavender",  hex: "#A78BFA"),  // Purple
        PaletteColor(id: 8, name: "Rose",      hex: "#F472B6"),  // Pink
        PaletteColor(id: 9, name: "Teal",      hex: "#2DD4BF"),  // Teal
    ]

    static func color(at index: Int) -> PaletteColor {
        colors[max(0, min(index, colors.count - 1))]
    }
}
