//
//  ScheduleActivityAttributes.swift
//  LHS Life
//
//  Shared between the app target and the widget extension target.
//
//  Design:
//  — Static attributes carry the full day schedule, written once at start.
//  — ContentState carries only which slot is current. The worker broadcasts
//    it at every bell on the school's channel (one push for every card, so
//    the bell may be another student's); a BGProcessingTask the app
//    schedules is the on-device fallback.
//  — The widget uses ContentState for text/color and ProgressView(timerInterval:)
//    for the live progress bar — no render budget consumed.
//

import ActivityKit
import Foundation

struct ScheduleActivityAttributes: ActivityAttributes {

    // MARK: - Static (written once at start)

    var schoolName: String
    var scheduleTypeName: String   // e.g. "Block Schedule", "Regular Schedule"

    /// Full day schedule — used by the widget to know all transitions.
    var schedule: [ScheduledPeriod]

    /// Set only on a PREVIEW card — the one Settings puts up to show what a
    /// Live Activity is. The widget draws
    /// it frozen from these values instead of the schedule: nothing counts
    /// down, nothing is sent to the server, and it says PREVIEW on it.
    ///
    /// Optional so the cards already on students' phones when this ships
    /// still decode: a missing key reads as nil, a real card.
    var preview: Preview? = nil

    struct Preview: Codable, Hashable {
        var className: String
        var colorHex: String
        var nextClassName: String
        var minutesLeft: Int
        var bellTime: String     // "10:50 AM"
        var progress: Double     // 0...1, never moves
    }

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
    // Broadcast by the worker at each bell (and set by the BGProcessingTask
    // fallback). The widget resolves it against its own schedule.

    public struct ContentState: Codable, Hashable {
        /// Minutes since midnight of the bell that just rang. The widget
        /// matches it against attributes.schedule; a bell that isn't one of
        /// this card's own falls back to the clock.
        var slotStartMinutes: Int
        /// True when the app ends the card; the widget shows "Done for today".
        var isEnded: Bool

        init(slotStartMinutes: Int = 0, isEnded: Bool = false) {
            self.slotStartMinutes = slotStartMinutes
            self.isEnded          = isEnded
        }
    }
}
