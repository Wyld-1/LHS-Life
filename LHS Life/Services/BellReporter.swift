//
//  BellReporter.swift
//  LHS Life
//
//  Tells the worker when this phone's bells ring today, so it knows when
//  to broadcast.
//
//  WHY ONLY BELL TIMES: every card listens on one broadcast channel
//  (AppConstants.broadcastChannel). At each bell the worker sends one push
//  to that channel, Apple fans it out to every subscribed phone, and each
//  card works out its own class from the schedule it carries plus the
//  clock. So the worker never needs to know WHO is listening — only the
//  union of everyone's bell times. That's all this sends: the day, the
//  minutes, and the APNs environment. No device ID, no token, no class
//  names.
//
//  WHEN: whenever a card starts (a schedule-change replacement is a start
//  too), and when the app reconnects to a running card after a relaunch.
//  Repeats are harmless — the worker merges them into a set — and they heal
//  a worker that lost the day's list.
//

import Foundation
import OSLog

enum BellReporter {

    /// The worker's clock is Pacific, and so is the school's.
    static let pacific: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()

    /// Every bell this card cares about: each period's start AND end, as
    /// minutes since midnight Pacific, deduplicated and sorted.
    ///
    /// Ends as well as starts: the last end is when the card turns to "Done
    /// for today", and a period that ends into a gap longer than a passing
    /// period has no next start to carry that change.
    ///
    /// Converted in Pacific rather than the phone's zone because the dates on
    /// the card are absolute instants: a phone set to another zone still
    /// needs its push at the instant its bell rings, which is the worker's
    /// Pacific minute.
    static func bellMinutes(
        for periods: [ScheduleActivityAttributes.ScheduledPeriod],
        calendar: Calendar = pacific
    ) -> [Int] {
        func minutes(_ date: Date) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        let all = periods.flatMap { [minutes($0.startDate), minutes($0.endDate)] }
        return Array(Set(all)).sorted()
    }

    /// Sends the card's bells to the worker. Fire-and-forget: the card is
    /// already on the Lock Screen and keeps its own time, so a lost report
    /// costs pushes, not the card. One retry covers the usual cause — a
    /// connection that hasn't come up yet right after the app opens.
    static func report(_ periods: [ScheduleActivityAttributes.ScheduledPeriod]) {
        guard let first = periods.first,
              let url = URL(string: "\(AppConstants.workerURL)/bells")
        else { return }

        struct Body: Encodable {
            let day: String          // "yyyy-MM-dd", Pacific
            let minutes: [Int]
            let environment: String  // "production" | "sandbox"
        }
        let body = Body(
            day: DateFormatter.isoDay.string(from: first.startDate),
            minutes: bellMinutes(for: periods),
            environment: InstallInfo.apnsEnvironment
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConstants.workerSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(body)

        Task {
            for attempt in 1...2 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200..<300).contains(status) {
                        LHSLogger.liveActivity.notice(
                            "Bells reported — \(body.day, privacy: .public) env: \(body.environment, privacy: .public) count: \(body.minutes.count) first: \(body.minutes.first ?? -1) last: \(body.minutes.last ?? -1)"
                        )
                    } else {
                        let text = String(data: data, encoding: .utf8) ?? "<no body>"
                        LHSLogger.liveActivity.error("Bells report FAILED — HTTP \(status): \(text, privacy: .public)")
                        IssueReporter.report(.registration, detail: "HTTP \(status): \(text)", subject: "bells")
                    }
                    return
                } catch {
                    // Only the phone's own connection is worth a second try;
                    // anything else would fail the same way again.
                    guard attempt == 1, IssueReporter.isConnectionProblem(error) else {
                        LHSLogger.liveActivity.error("Bells report network error — \(String(describing: error), privacy: .public)")
                        return
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }
}
