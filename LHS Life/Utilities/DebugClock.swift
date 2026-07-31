//
//  DebugClock.swift
//  LHS Life
//
//  Screenshot tool, not a shipping feature.
//
//  Two independent overrides:
//  1. overrideDate — fakes "now" for the calendar's Now-ticker (which day
//     counts as "today", and where vertically the ticker sits). Flows
//     through the real Grid.y(for:on:) math, same as before.
//  2. forcedPrimaryText / forcedSecondaryText / forcedProgress — bypass the
//     header pill's real schedule-state computation entirely. Faking a
//     believable "now" that flows correctly through schedule lookup +
//     ScheduleEngine + period matching is fragile for a one-off screenshot
//     (every piece has to line up perfectly); directly forcing the
//     rendered text/progress is simpler and can't produce nonsense output
//     regardless of what schedule data does or doesn't exist.
//
//  Only reachable from the existing debugSection in SettingsSheetView.
//

import Foundation
import Observation

@MainActor
@Observable
final class DebugClock {
    static let shared = DebugClock()
    private init() {}

    var overrideDate: Date? = nil
    var now: Date { overrideDate ?? Date() }

    var forcedPrimaryText: String? = nil
    var forcedSecondaryText: String? = nil
    /// 0...1, nil = use the real computed progress.
    var forcedProgress: Double? = nil
}
