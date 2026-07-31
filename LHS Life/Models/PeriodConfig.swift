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

    /// Default color index per period: LaSalle Blue (0, 6, 8 — the "no
    /// custom color chosen" slots), red, orange, yellow, green, sky,
    /// LaSalle Blue, lavender, LaSalle Blue.
    /// Slate (index 0) is intentionally never assigned — it still exists
    /// in ColorPalette.colors for index stability with any already-saved
    /// data, but is excluded from the picker (see ColorPickerPopup) and
    /// from these defaults, since flat gray read as "depressing and
    /// forgettable" rather than as a real default.
    private static let defaultColorIndices = [6, 1, 2, 3, 4, 5, 6, 7, 6]

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
