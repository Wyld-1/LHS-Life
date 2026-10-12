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
    /// A running fake clock: "now" is the real time shifted by this much, so
    /// it keeps ticking — for screen recordings where the header has to count
    /// down for real. Set from the -demoClock launch argument. 0 = real time.
    var offset: TimeInterval = 0
    var now: Date { overrideDate ?? Date().addingTimeInterval(offset) }

    #if DEBUG
    /// Reads `-demoClock "yyyy-MM-dd HH:mm"` from the launch arguments (they
    /// land in UserDefaults' argument domain) and starts the clock there.
    /// Returns true if it did.
    @discardableResult
    func applyLaunchArgument() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: "demoClock") else { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        guard let target = f.date(from: raw) else { return false }
        offset = target.timeIntervalSinceNow
        return true
    }
    #endif

    var forcedPrimaryText: String? = nil
    var forcedSecondaryText: String? = nil
    /// 0...1, nil = use the real computed progress.
    var forcedProgress: Double? = nil
}
