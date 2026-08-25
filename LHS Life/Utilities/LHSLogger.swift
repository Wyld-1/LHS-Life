//
//  LHSLogger.swift
//  LHS Life
//
//  Lightweight tagged logger. All output goes to os.Logger — visible in
//  Console.app (filter subsystem = "lhslife") and Xcode's debug console.
//
//  Usage:
//    LHSLogger.ical.debug("fetched \(n) events")
//    LHSLogger.parser.error("no schedules built")
//
//  TEMPORARY — added 2026-05-29 to diagnose missing finals schedule bug.
//  Remove or gate behind a build flag once root cause is confirmed.
//

import OSLog

enum LHSLogger {
    /// iCal fetch + parse pipeline
    static let ical     = Logger(subsystem: "lhslife", category: "ical")
    /// BellScheduleParser / FinalExamParser decisions
    static let parser   = Logger(subsystem: "lhslife", category: "parser")
    /// CalendarStore.applyEvents + schedule dictionary
    static let store    = Logger(subsystem: "lhslife", category: "store")
    /// ScheduleEngine / todayState
    static let engine   = Logger(subsystem: "lhslife", category: "engine")
    /// Grad-year / Pathways / senior checks
    static let gradYear = Logger(subsystem: "lhslife", category: "gradYear")
    /// Live Activity start/end decisions and push token registration.
    ///
    /// Use .notice or .error here, never .debug: debug-level messages aren't
    /// persisted by default, so they're invisible when inspecting a TestFlight
    /// build in Console.app — which is the entire reason this category exists.
    static let liveActivity = Logger(subsystem: "lhslife", category: "liveActivity")
}
