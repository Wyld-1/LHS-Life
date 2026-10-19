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
//  WHAT IS SENT: a random per-install ID (InstallInfo.deviceId), the app
//  build, the iOS version, and a short description of the failure. Never a
//  name, an email address, a class schedule, or anything typed into the app.
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
    /// fix a calendar entry, repost a schedule, look at the worker.
    /// A student's own flaky wifi is not on it.
    enum Kind: String {
        /// The CalendarWiz feed didn't answer, or didn't parse.
        case calendarFetch      = "calendar_fetch"
        /// A day's schedule was posted as a picture the app couldn't read.
        case scheduleImage      = "schedule_image"
        /// ActivityKit refused to start the Live Activity.
        case liveActivityStart  = "live_activity_start"
        /// The worker refused or failed a report of today's bells
        /// (subject "bells"). The raw value predates bell reports and stays
        /// so the worker's /status page keeps grouping it the same way.
        case registration       = "registration"
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

        // Read here, on the main actor (UIDevice and AppConstants live
        // there), and handed to the background task as plain values.
        let deviceId = InstallInfo.deviceId
        let appVersion = InstallInfo.appVersion
        let osVersion = InstallInfo.osVersion
        let workerURL = AppConstants.workerURL
        let workerSecret = AppConstants.workerSecret

        Task.detached(priority: .background) {
            guard let url = URL(string: "\(workerURL)/report") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(workerSecret)", forHTTPHeaderField: "Authorization")
            struct Body: Encodable {
                let deviceId: String
                let kind: String
                let subject: String
                let detail: String
                let appVersion: String
                let osVersion: String
            }
            request.httpBody = try? JSONEncoder().encode(Body(
                deviceId: deviceId,
                kind: kind.rawValue,
                subject: String(subject.prefix(40)),
                // Truncated here as well as on the worker: the whole record
                // lives in KV metadata, which is capped at 1 KB.
                detail: String(detail.prefix(160)),
                appVersion: appVersion,
                osVersion: osVersion
            ))
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - Is it the school's problem?

    /// A request that was cancelled, not one that failed — the view that
    /// started it went away, or a newer refresh replaced it.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// The device's own connection failing: no signal, a dropped connection,
    /// a timeout. One of these from one phone is a student on bad wifi, not
    /// a broken server — but a hundred of them at once could be the server,
    /// so callers retry first and report what's left under the subject
    /// "network", apart from "server" failures that are always the school's.
    static func isConnectionProblem(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorDataNotAllowed,           // cellular data off for the app
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            // Couldn't look up the address. From one phone that's no internet
            // or a wifi sign-in page, not the school's server — these were
            // landing under "server" at 9 PM. If a school address really
            // stopped resolving, "network" would show it as many devices.
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
        ].contains(ns.code)
    }

    /// Whether this device has reported any problem today. ReviewPrompter
    /// uses it to avoid asking for a rating on a day something broke.
    static var hasReportedToday: Bool {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        return UserDefaults.standard.dictionaryRepresentation().keys.contains {
            $0.hasPrefix("lhs_issue_") && $0.hasSuffix("_\(dayKey)")
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
