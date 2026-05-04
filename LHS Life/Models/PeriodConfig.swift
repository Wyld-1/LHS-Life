//
//  PeriodConfig.swift
//  LaSalle Schedule
//
//  Per-period user configuration: custom name, color, and enabled toggle.
//  Shared between app and widget targets — no UIKit/SwiftUI imports.
//
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation

/// User-configured settings for a single period slot.
struct PeriodConfig: Identifiable, Codable, Hashable {
    let id: Int              // Period number: 0–8
    var customName: String   // e.g. "Chemistry", "AP Lit"
    var colorIndex: Int      // Index into ColorPalette.colors (0–9)
    var isEnabled: Bool      // Whether this period is part of the student's schedule

    /// Display name: custom if set, otherwise "Period N"
    var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (id == 0 ? "Period 0" : "Period \(id)") : trimmed
    }

    /// Default color index per period: gray, red, orange, yellow, green, sky, blue, lavender, gray
    private static let defaultColorIndices = [0, 1, 2, 3, 4, 5, 6, 7, 0]

    /// Default configs for all period slots.
    static let defaults: [PeriodConfig] = (0...8).map { n in
        PeriodConfig(
            id: n,
            customName: "",
            colorIndex: defaultColorIndices[n],
            isEnabled: !(n == 0 || n == 8)
        )
    }
}
