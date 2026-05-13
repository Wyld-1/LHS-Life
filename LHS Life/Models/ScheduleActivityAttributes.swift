//
//  ScheduleActivityAttributes.swift
//  LHS Life
//
//  Shared between the app target and the widget extension target.
//
//  Design: the full day schedule is written into static attributes at start.
//  ContentState carries nothing meaningful — the widget computes everything
//  from attributes.schedule and context.date via TimelineView.
//  No updates are ever needed after the activity starts.
//

import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {

    // MARK: - Static (written once at start, never changes)

    var schoolName: String

    /// Every period in today's schedule, in order.
    /// The widget uses this + context.date to know what to display at any moment.
    var schedule: [ScheduledPeriod]

    // MARK: - Scheduled Period

    struct ScheduledPeriod: Codable, Hashable {
        /// Period number (1–8). Nil for Break, Lunch, Advisory etc.
        var periodNumber: Int?
        /// Display name fallback if user has no config (e.g. "Lunch", "Break")
        var fallbackName: String
        /// Hex color string — resolved from user's PeriodConfig at start time.
        /// Gray (#94A3B8) for non-period slots.
        var colorHex: String
        /// Absolute start of this slot.
        var startDate: Date
        /// Absolute end of this slot.
        var endDate: Date

        /// Formatted end time string, e.g. "10:50 AM". Pre-computed at start.
        var endTimeString: String
    }

    // MARK: - ContentState
    //
    // Intentionally minimal. The widget derives everything from attributes.schedule
    // and context.date. ContentState only carries the isEnded flag so the app
    // can signal after-school cleanup without the widget needing to know the time.

    public struct ContentState: Codable, Hashable {
        var isEnded: Bool = false
    }
}
