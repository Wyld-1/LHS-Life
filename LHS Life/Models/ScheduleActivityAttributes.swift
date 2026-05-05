//
//  ScheduleActivityAttributes.swift
//  LHS Life
//
//  Shared between the app target and the widget extension target.
//  Add this file to: LHS Life target + LHS Widgets target
//
//  Static attributes: things that don't change for the life of the activity.
//  ContentState: the data that updates every second.
//

import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {

    // MARK: - Static (set once at start, never changes)

    /// The period color as a hex string — read by the widget to tint the UI.
    var periodColorHex: String
    /// School name for branding
    var schoolName: String

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable {
        /// Display name of the current period ("Chemistry", "Period 3", "Lunch")
        var currentPeriodName: String
        /// Seconds remaining in the current period
        var secondsRemaining: Int
        /// Total duration of the current period in seconds (for progress calculation)
        var periodDurationSeconds: Int
        /// Display name of the next period (nil if this is the last period)
        var nextPeriodName: String?
        /// True when school is not in session (weekend text, etc.)
        var isOffSchedule: Bool
        /// The primary header text — mirrors what the app header shows
        var headerText: String

        // MARK: Computed

        var progress: Double {
            guard periodDurationSeconds > 0 else { return 0 }
            let elapsed = periodDurationSeconds - secondsRemaining
            return min(1.0, max(0.0, Double(elapsed) / Double(periodDurationSeconds)))
        }

        var timeRemainingText: String {
            if secondsRemaining <= 0 { return "Done" }
            let mins = secondsRemaining / 60
            let secs = secondsRemaining % 60
            if mins > 0 { return "\(mins)m \(secs)s" }
            return "\(secs)s"
        }
    }
}
