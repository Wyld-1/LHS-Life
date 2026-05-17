//
//  ScheduleActivityAttributes.swift
//  LHS Life
//
//  Shared between the app target and the widget extension target.
//
//  Design:
//  — Static attributes carry the full day schedule, written once at start.
//  — ContentState carries the CURRENT period's display data, pushed at each
//    bell transition by a BGProcessingTask the app schedules at launch.
//  — The widget uses ContentState for text/color and ProgressView(timerInterval:)
//    for the live progress bar — no render budget consumed.
//

import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {

    // MARK: - Static (written once at start)

    var schoolName: String

    /// Full day schedule — used by the widget to know all transitions.
    var schedule: [ScheduledPeriod]

    // MARK: - Scheduled Period

    struct ScheduledPeriod: Codable, Hashable {
        var periodNumber: Int?
        var displayName: String
        var colorHex: String
        var startDate: Date
        var endDate: Date
        var endTimeString: String
    }

    // MARK: - ContentState
    // Pushed at each bell transition by a BGProcessingTask.
    // Widget renders directly from these values.

    public struct ContentState: Codable, Hashable {
        /// Display name of the current period — "Chemistry", "Lunch", etc.
        var currentPeriodName: String
        /// Hex color for the current period's accent
        var colorHex: String
        /// Absolute start of current period — for ProgressView(timerInterval:)
        var periodStartDate: Date
        /// Absolute end of current period — for ProgressView(timerInterval:)
        var periodEndDate: Date
        /// Display name of next period, nil if last period
        var nextPeriodName: String?
        /// Formatted next bell time string, e.g. "10:50 AM"
        var nextBellTime: String?
        /// True when the app signals end of day
        var isEnded: Bool

        init(
            currentPeriodName: String = "",
            colorHex: String = "#94A3B8",
            periodStartDate: Date = Date(),
            periodEndDate: Date = Date().addingTimeInterval(3600),
            nextPeriodName: String? = nil,
            nextBellTime: String? = nil,
            isEnded: Bool = false
        ) {
            self.currentPeriodName = currentPeriodName
            self.colorHex          = colorHex
            self.periodStartDate   = periodStartDate
            self.periodEndDate     = periodEndDate
            self.nextPeriodName    = nextPeriodName
            self.nextBellTime      = nextBellTime
            self.isEnded           = isEnded
        }
    }
}
