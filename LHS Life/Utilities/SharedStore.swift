//
//  SharedStore.swift
//  LaSalle Schedule
//
//  Thin read/write bridge between the app and the widget/Live Activity extensions
//  via the App Group. The app writes here after every fetch; widgets read from here.
//
//  Deliberately simple: one blob of encoded events + one blob of bell schedules.
//  Widgets never need to parse iCal — they just read pre-processed data.
//
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation

enum SharedStore {

    private static let suite = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard

    // MARK: - Keys

    private enum Keys {
        static let events        = "shared_events"
        static let bellSchedules = "shared_bell_schedules"
        static let lastUpdated   = "shared_last_updated"
    }

    // MARK: - Write (app only)

    static func write(events: [SchoolEvent], bellSchedules: [String: BellSchedule]) {
        let encoder = JSONEncoder()
        if let evData = try? encoder.encode(events) {
            suite.set(evData, forKey: Keys.events)
        }
        if let bsData = try? encoder.encode(bellSchedules) {
            suite.set(bsData, forKey: Keys.bellSchedules)
        }
        suite.set(Date(), forKey: Keys.lastUpdated)
    }

    // MARK: - Read (app + widgets)

    static func readEvents() -> [SchoolEvent] {
        guard let data = suite.data(forKey: Keys.events),
              let decoded = try? JSONDecoder().decode([SchoolEvent].self, from: data)
        else { return [] }
        return decoded
    }

    static func readBellSchedules() -> [String: BellSchedule] {
        guard let data = suite.data(forKey: Keys.bellSchedules),
              let decoded = try? JSONDecoder().decode([String: BellSchedule].self, from: data)
        else { return [:] }
        return decoded
    }

    static func readBellSchedule(for dayKey: String) -> BellSchedule? {
        readBellSchedules()[dayKey]
    }

    static var lastUpdated: Date? {
        suite.object(forKey: Keys.lastUpdated) as? Date
    }

    /// True if the shared data is older than the given interval (default 1 hour).
    static func isStale(olderThan interval: TimeInterval = 3600) -> Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > interval
    }
}
