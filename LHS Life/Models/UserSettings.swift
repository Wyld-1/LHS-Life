//
//  UserSettings.swift
//  LHS Life
//
//  @Observable — no Combine needed.
//  Add this file to: LHS Life target + LHS Widgets target
//

import Foundation
import Observation

// MARK: - Live Activity Mode

enum LiveActivityMode: Int, Codable, CaseIterable {
    case off           = 0
    case everyDay      = 1
    case abnormalOnly  = 2

    var label: String {
        switch self {
        case .off:          return "Off"
        case .everyDay:     return "Every Day"
        case .abnormalOnly: return "Abnormal Days"
        }
    }

    var description: String {
        switch self {
        case .off:          return "Never show live bell schedule"
        case .everyDay:     return "Always show live bell schedule"
        case .abnormalOnly: return "Only on days with liturgy, early release, etc."
        }
    }
}

/// Three states for each ASB work day.
/// Stored as Int raw values so [ASBDayMode] encodes cleanly to UserDefaults.
enum ASBDayMode: Int, Codable, CaseIterable {
    case off                   = 0  // gray  — no notifications
    case announcementsAndStore = 1 // blue — announcement + student store
    case announcementsOnly     = 2  // orange  — announcement reminder only

    var color: String {
        switch self {
        case .off:                   return "#94A3B8"  // Slate
        case .announcementsAndStore: return "#3A6FD8"  // LaSalle Blue
        case .announcementsOnly:     return "#FB923C"  // Peach/Orange
        }
    }

    var label: String {
        switch self {
        case .off:                   return "Off"
        case .announcementsAndStore: return "Announcements & Store"
        case .announcementsOnly:     return "Announcements"
        }
    }

    /// Cycles to the next state
    var next: ASBDayMode {
        switch self {
        case .off:                   return .announcementsAndStore
        case .announcementsAndStore: return .announcementsOnly
        case .announcementsOnly:     return .off
        }
    }
}

// MARK: - UserSettings

@Observable
final class UserSettings {

    static let appGroupID = "group.lasalle.widgetinfo"
    @ObservationIgnored private let store: UserDefaults
    static let shared = UserSettings()

    // MARK: - State

    var hasCompletedOnboarding: Bool
    var graduationYear: Int
    var periodConfigs: [PeriodConfig]
    var professionalDressNotificationsEnabled: Bool
    var liveActivityMode: LiveActivityMode
    /// Temporary per-day override: Live Activity enabled just for today.
    var liveActivityEnabledToday: Bool
    @ObservationIgnored private var liveActivityTodayKey: String = ""

    // MARK: - ASB

    var isASBMember: Bool
    /// Three-state mode per weekday (Mon=0…Fri=4)
    var asbWorkDays: [ASBDayMode]  // 5 elements

    // MARK: - Init

    init() {
        let d = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard
        self.store = d

        self.hasCompletedOnboarding = d.bool(forKey: Keys.onboarding)

        let storedYear = d.integer(forKey: Keys.gradYear)
        self.graduationYear = storedYear == 0 ? Self.defaultGradYear : storedYear

        if let data = d.data(forKey: Keys.periodConfigs),
           let decoded = try? JSONDecoder().decode([PeriodConfig].self, from: data),
           d.integer(forKey: Keys.paletteVersion) == Self.currentPaletteVersion {
            self.periodConfigs = decoded
        } else {
            self.periodConfigs = PeriodConfig.defaults
            d.set(Self.currentPaletteVersion, forKey: Keys.paletteVersion)
        }

        self.professionalDressNotificationsEnabled = d.object(forKey: Keys.dressNotifs) as? Bool ?? true
        let rawMode = d.integer(forKey: Keys.liveActivityMode)
        self.liveActivityMode = LiveActivityMode(rawValue: rawMode) ?? .off
        self.isASBMember = d.bool(forKey: Keys.asbMember)

        // Decode ASBDayMode array
        if let data = d.data(forKey: Keys.asbWorkDays),
           let decoded = try? JSONDecoder().decode([ASBDayMode].self, from: data),
           decoded.count == 5 {
            self.asbWorkDays = decoded
        } else {
            self.asbWorkDays = Array(repeating: .off, count: 5)
        }

        // Per-day Live Activity override — check if it's still today
        let todayKey = DateFormatter.isoDay.string(from: Date())
        let savedKey = d.string(forKey: Keys.liveActivityTodayKey) ?? ""
        self.liveActivityEnabledToday = savedKey == todayKey && d.bool(forKey: Keys.liveActivityToday)
        self.liveActivityTodayKey = todayKey
    }

    // MARK: - Live Activity effective state

    /// True if Live Activities should run right now.
    /// Pass the current schedule type so .abnormalOnly can activate automatically.
    func liveActivityEffectivelyEnabled(scheduleType: ScheduleType?) -> Bool {
        let todayKey = DateFormatter.isoDay.string(from: Date())
        if todayKey != liveActivityTodayKey {
            liveActivityEnabledToday = false
            liveActivityTodayKey = todayKey
        }
        switch liveActivityMode {
        case .off:          return liveActivityEnabledToday
        case .everyDay:     return true
        case .abnormalOnly:
            let abnormal: Set<ScheduleType> = [.lateStart, .earlyRelease, .assembly, .custom]
            return abnormal.contains(scheduleType ?? .unknown)
        }
    }

    /// Backwards-compat computed var for callers without schedule context.
    var liveActivityEffectivelyEnabled: Bool {
        liveActivityEffectivelyEnabled(scheduleType: nil)
    }

    /// Enable Live Activity just for today.
    func enableLiveActivityForToday() {
        let todayKey = DateFormatter.isoDay.string(from: Date())
        liveActivityEnabledToday = true
        liveActivityTodayKey = todayKey
        store.set(true, forKey: Keys.liveActivityToday)
        store.set(todayKey, forKey: Keys.liveActivityTodayKey)
    }

    // MARK: - Save

    func save() {
        store.set(hasCompletedOnboarding, forKey: Keys.onboarding)
        store.set(graduationYear, forKey: Keys.gradYear)
        store.set(professionalDressNotificationsEnabled, forKey: Keys.dressNotifs)
        store.set(liveActivityMode.rawValue, forKey: Keys.liveActivityMode)
        store.set(isASBMember, forKey: Keys.asbMember)
        if let data = try? JSONEncoder().encode(periodConfigs) {
            store.set(data, forKey: Keys.periodConfigs)
        }
        if let data = try? JSONEncoder().encode(asbWorkDays) {
            store.set(data, forKey: Keys.asbWorkDays)
        }
    }

    // MARK: - Helpers

    func config(for periodID: Int) -> PeriodConfig? {
        periodConfigs.first { $0.id == periodID }
    }

    func updateConfig(_ config: PeriodConfig) {
        guard let i = periodConfigs.firstIndex(where: { $0.id == config.id }) else { return }
        periodConfigs[i] = config
    }

    private static var defaultGradYear: Int {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let year  = comps.year ?? 2026
        let month = comps.month ?? 1
        return month >= 8 ? year + 2 : year + 1
    }

    private enum Keys {
        static let onboarding           = "onboarding_complete"
        static let gradYear             = "graduation_year"
        static let periodConfigs        = "period_configs"
        static let dressNotifs          = "dress_notifications_enabled"
        static let liveActivityMode      = "live_activity_mode"
        static let abnormalNotifs        = "abnormal_schedule_notifications"  // legacy, unused
        static let liveActivityToday    = "live_activity_today"
        static let liveActivityTodayKey = "live_activity_today_key"
        static let paletteVersion       = "palette_version"
        static let asbMember            = "asb_member"
        static let asbWorkDays          = "asb_work_days"
    }

    private static let currentPaletteVersion = 2
}
