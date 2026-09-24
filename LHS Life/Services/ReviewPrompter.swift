//
//  ReviewPrompter.swift
//  LHS Life
//
//  Decides when to ask for an App Store rating.
//
//  HOW THE PROMPT ACTUALLY WORKS: the app never shows it. It asks iOS, via
//  requestReview(), and iOS decides whether a prompt appears at all — at most
//  three times a year per person, never in TestFlight, and not if they've
//  turned "In-App Ratings & Reviews" off. So a request can silently do
//  nothing, and there's no way to tell. That's by design, and it's why the
//  job here is only to ask at a good MOMENT, not to count on being heard.
//
//  A GOOD MOMENT, per Apple's guidance: after someone has clearly gotten
//  value from the app, never on first launch, never mid-task, and never
//  right after something went wrong. Concretely:
//
//    - they've opened it on at least 5 different days, over at least 10
//      calendar days — a habit, not a first impression
//    - nothing has broken today (see IssueReporter) — asking for five stars
//      on the morning the calendar wouldn't load is how one-star reviews
//      get written
//    - at most once per app version, and 120 days apart — well inside
//      Apple's own cap, so the few requests that exist land where they count
//
//  The moment itself (the Events tab, nothing open, a few seconds after the
//  app comes forward) is chosen by AppTabContainer, which knows what's on
//  screen.
//

import Foundation

enum ReviewPrompter {

    private static let minimumActiveDays = 5
    private static let minimumDaysSinceFirstUse = 10
    private static let minimumDaysBetweenAsks = 120

    private enum Keys {
        static let firstUseDay     = "lhs_review_first_use_day"
        static let lastActiveDay   = "lhs_review_last_active_day"
        static let activeDayCount  = "lhs_review_active_day_count"
        static let lastAskedDate   = "lhs_review_last_asked_date"
        static let lastAskedVersion = "lhs_review_last_asked_version"
    }

    private static var defaults: UserDefaults { .standard }
    private static var todayKey: String { DateFormatter.isoDay.string(from: Date()) }
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Counts today as a day of use. Safe to call as often as you like —
    /// only the first call of each day counts.
    static func recordActiveDay() {
        let today = todayKey
        if defaults.string(forKey: Keys.firstUseDay) == nil {
            defaults.set(today, forKey: Keys.firstUseDay)
        }
        guard defaults.string(forKey: Keys.lastActiveDay) != today else { return }
        defaults.set(today, forKey: Keys.lastActiveDay)
        defaults.set(defaults.integer(forKey: Keys.activeDayCount) + 1, forKey: Keys.activeDayCount)
    }

    /// Everything about the person's history says it's fine to ask. Whether
    /// the SCREEN is in a fit state is the caller's call.
    static var isGoodTimeToAsk: Bool {
        guard defaults.integer(forKey: Keys.activeDayCount) >= minimumActiveDays else { return false }

        guard let firstUse = defaults.string(forKey: Keys.firstUseDay)
                .flatMap({ DateFormatter.isoDay.date(from: $0) }),
              daysSince(firstUse) >= minimumDaysSinceFirstUse
        else { return false }

        if defaults.string(forKey: Keys.lastAskedVersion) == appVersion { return false }
        if let lastAsked = defaults.object(forKey: Keys.lastAskedDate) as? Date,
           daysSince(lastAsked) < minimumDaysBetweenAsks {
            return false
        }

        return !IssueReporter.hasReportedToday
    }

    /// Records that a request was made. Called just before requestReview(),
    /// since whether iOS actually showed anything can't be known.
    static func markAsked() {
        defaults.set(Date(), forKey: Keys.lastAskedDate)
        defaults.set(appVersion, forKey: Keys.lastAskedVersion)
    }

    /// Delete All Data: a reset device starts the clock over.
    static func reset() {
        for key in [Keys.firstUseDay, Keys.lastActiveDay, Keys.activeDayCount,
                    Keys.lastAskedDate, Keys.lastAskedVersion] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func daysSince(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: Date())).day ?? 0
    }
}
