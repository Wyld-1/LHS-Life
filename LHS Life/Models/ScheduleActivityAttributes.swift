//
//  ScheduleActivityAttributes.swift
//  LHS Life
//
//  Shared between the app target and the widget extension target.
//  Add this file to: LHS Life target + LHS Widgets target
//
//  Copied from LHS Live — the working implementation on iOS 26.5.
//  Uses integer seconds + formatted time strings rather than Dates.
//

import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {

    // MARK: - Static

    var periodColorHex: String
    var schoolName: String

    // MARK: - Dynamic

    public struct ContentState: Codable, Hashable {
        /// Display name of the current period or state
        var currentPeriodName: String
        /// Seconds remaining in the current period (for progress)
        var secondsRemaining: Int
        /// Total duration of current period in seconds (for progress)
        var periodDurationSeconds: Int
        /// Display name of the next period
        var nextPeriodName: String?
        /// Time of the next bell as a formatted string e.g. "10:50 AM"
        var nextBellTime: String?
        /// True when school is not in session
        var isOffSchedule: Bool
        /// Mirrors the app header primary text
        var headerText: String

        // MARK: Computed

        var progress: Double {
            guard periodDurationSeconds > 0 else { return 0 }
            let elapsed = periodDurationSeconds - secondsRemaining
            return min(1.0, max(0.0, Double(elapsed) / Double(periodDurationSeconds)))
        }
    }
}
