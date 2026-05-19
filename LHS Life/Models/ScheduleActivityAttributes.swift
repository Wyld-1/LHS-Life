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
        /// Minutes since midnight identifying which slot just started.
        /// Widget matches this against attributes.schedule to resolve name/color/dates.
        var slotStartMinutes: Int
        /// True when the app signals end of day
        var isEnded: Bool

        init(slotStartMinutes: Int = 0, isEnded: Bool = false) {
            self.slotStartMinutes = slotStartMinutes
            self.isEnded          = isEnded
        }
    }
}
