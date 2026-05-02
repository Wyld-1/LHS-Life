//
//  ColorPalette.swift
//  LaSalle Schedule
//
//  10 curated colors that all look great on a dark background.
//  LaSalle blue and gold anchor the palette; the rest complement them.
//  Stored as hex strings so this file is safe in both app and widget targets
//  with no SwiftUI/UIKit import — UI layers convert to Color/UIColor themselves.
//
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation

enum ColorPalette {

    struct PaletteColor: Identifiable, Codable, Hashable {
        let id: Int
        let name: String
        let hex: String    // e.g. "#003DA5"
    }

    /// The 10 available period colors.
    static let colors: [PaletteColor] = [
        PaletteColor(id: 0, name: "LaSalle Blue",  hex: "#3A6FD8"),  // Royal blue, lightened for dark bg
        PaletteColor(id: 1, name: "Gold",           hex: "#F5B800"),  // LaSalle gold
        PaletteColor(id: 2, name: "Emerald",        hex: "#34C78A"),  // Green
        PaletteColor(id: 3, name: "Coral",          hex: "#FF6B6B"),  // Red-orange
        PaletteColor(id: 4, name: "Lavender",       hex: "#A78BFA"),  // Purple
        PaletteColor(id: 5, name: "Sky",            hex: "#38BDF8"),  // Light blue
        PaletteColor(id: 6, name: "Peach",          hex: "#FB923C"),  // Orange
        PaletteColor(id: 7, name: "Rose",           hex: "#F472B6"),  // Pink
        PaletteColor(id: 8, name: "Mint",           hex: "#2DD4BF"),  // Teal
        PaletteColor(id: 9, name: "Slate",          hex: "#94A3B8"),  // Neutral gray-blue
    ]

    static func color(at index: Int) -> PaletteColor {
        colors[max(0, min(index, colors.count - 1))]
    }
}
