//
//  IssueReporter.swift
//  LHS Life
//
//  Tells the worker when something is broken, so the school can see it on
//  WORKER-URL/status instead of hearing about it from a student.
//
//  WHY NOT EMAIL: the first plan was to mail techcenter@lasalleyakima.org on
//  every failure. One calendar outage would then send a mail per device per
//  retry — hundreds before first period — and an inbox that behaves like that
//  gets a filter rule within a week. A count on a page answers the only
//  question that matters ("is this one student or all of them?") without
//  anyone having to read anything.
//
//  WHAT IS SENT: the anonymous device ID the app already registers with, the
//  app build, the iOS version, and a short description of the failure. Never
//  a name, an email address, a class schedule, or anything typed into the app.
//
//  HOW OFTEN: once per device per kind per day. A phone with no signal
//  reports "calendar unreachable" once, not every thirty seconds when the
//  refresh retries — and the daily reset means a problem that is still
//  happening tomorrow shows up again tomorrow.
//

import Foundation
import OSLog

enum IssueReporter {

    /// The kinds of failure worth a school's attention. Deliberately a closed
    /// list: these are the ones where someone at school can DO something —
    /// fix a calendar entry, repost a schedule, ask for a server upgrade.
    /// A student's own flaky wifi is not on it.
    enum Kind: String {
        /// The CalendarWiz feed didn't answer, or didn't parse.
        case calendarFetch      = "calendar_fetch"
        /// A day's schedule was posted as a picture the app couldn't read.
        case scheduleImage      = "schedule_image"
        /// ActivityKit refused to start the Live Activity.
        case liveActivityStart  = "live_activity_start"
        /// The worker refused or failed the push registration.
        case registration       = "registration"
        /// The worker is full — the signal that it needs a plan upgrade.
        case overCapacity       = "over_capacity"
        /// PowerSchool / Schoology / lunch ordering wouldn't load.
        case webLoad            = "web_load"
    }

    /// Reports `kind` unless this device already reported it today.
    ///
    /// `subject` separates things that share a kind but are different
    /// problems — Schoology being down is not PowerSchool being down, and
    /// Tuesday's unreadable schedule picture is not Thursday's. Without it
    /// the first one reported each day would hide the rest.
    ///
    /// Fire-and-forget by design: a failure to report a failure is not worth
    /// a retry, and must never be able to slow down or break the thing that
    /// was already going wrong.
    static func report(_ kind: Kind, detail: String, subject: String = "") {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let seenKey = "lhs_issue_\(kind.rawValue)_\(subject)_\(dayKey)"
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        // Yesterday's marks are dead weight — they can never match again,
        // since the key carries today's date. Without this a phone would
        // accumulate one stale setting per problem it ever reported, for the
        // whole school year.
        pruneMarks(keeping: dayKey)
        // Set BEFORE the request, not after: two failures a second apart
        // would otherwise both pass this check and send.
        UserDefaults.standard.set(true, forKey: seenKey)

        LHSLogger.ical.error("Issue reported: \(kind.rawValue, privacy: .public) — \(detail, privacy: .public)")

        Task.detached(priority: .background) {
            guard let url = URL(string: "\(AppConstants.workerURL)/report") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppConstants.workerSecret)", forHTTPHeaderField: "Authorization")
            struct Body: Encodable {
                let deviceId: String
                let kind: String
                let subject: String
                let detail: String
                let appVersion: String
                let osVersion: String
            }
            request.httpBody = try? JSONEncoder().encode(Body(
                deviceId: PushTokenService.deviceId,
                kind: kind.rawValue,
                subject: String(subject.prefix(40)),
                // Truncated here as well as on the worker: the whole record
                // lives in KV metadata, which is capped at 1 KB.
                detail: String(detail.prefix(160)),
                appVersion: PushTokenService.appVersion,
                osVersion: PushTokenService.osVersion
            ))
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Drops every "already reported" mark from a day other than `dayKey`.
    private static func pruneMarks(keeping dayKey: String) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("lhs_issue_") && !key.hasSuffix("_\(dayKey)") {
            defaults.removeObject(forKey: key)
        }
    }

    /// Clears today's "already reported" marks. Called by Delete All Data so a
    /// reset device behaves like a fresh one.
    static func resetDedupe() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("lhs_issue_") {
            defaults.removeObject(forKey: key)
        }
    }
}
