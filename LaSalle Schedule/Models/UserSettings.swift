//
//  UserSettings.swift
//  LaSalle Schedule
//
//  @Observable replaces ObservableObject + @Published + Combine.
//  The Observation framework is available in all targets (app + widget)
//  on iOS 17+. No Combine import needed.
//
//  Add this file to: LaSalle Schedule target + LaSalle Schedule Widgets target
//

import Foundation
import Observation

@Observable
final class UserSettings {

    // MARK: - App Group

    static let appGroupID = "group.lasalle.widgetinfo"

    @ObservationIgnored private let store: UserDefaults

    // MARK: - Singleton
    // Created once at the App level and passed via .environment().
    // Never create with @State inside a view — @State reinitializes on rebuilds.

    static let shared = UserSettings()

    // MARK: - State
    // All stored properties are automatically tracked by @Observable.
    // No @Published needed.

    var hasCompletedOnboarding: Bool
    var graduationYear: Int
    var periodConfigs: [PeriodConfig]
    var professionalDressNotificationsEnabled: Bool
    var liveActivityEnabled: Bool

    // MARK: - Init (reads from disk exactly once)

    init() {
        let d = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard
        self.store = d

        self.hasCompletedOnboarding = d.bool(forKey: Keys.onboarding)

        let storedYear = d.integer(forKey: Keys.gradYear)
        self.graduationYear = storedYear == 0 ? Self.defaultGradYear : storedYear

        if let data = d.data(forKey: Keys.periodConfigs),
           let decoded = try? JSONDecoder().decode([PeriodConfig].self, from: data) {
            self.periodConfigs = decoded
        } else {
            self.periodConfigs = PeriodConfig.defaults
        }

        self.professionalDressNotificationsEnabled = d.object(forKey: Keys.dressNotifs) as? Bool ?? true
        self.liveActivityEnabled = d.object(forKey: Keys.liveActivity) as? Bool ?? false
    }

    // MARK: - Explicit save (called on settings sheet dismiss only)

    func save() {
        store.set(hasCompletedOnboarding, forKey: Keys.onboarding)
        store.set(graduationYear, forKey: Keys.gradYear)
        store.set(professionalDressNotificationsEnabled, forKey: Keys.dressNotifs)
        store.set(liveActivityEnabled, forKey: Keys.liveActivity)
        if let data = try? JSONEncoder().encode(periodConfigs) {
            store.set(data, forKey: Keys.periodConfigs)
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
        static let onboarding    = "onboarding_complete"
        static let gradYear      = "graduation_year"
        static let periodConfigs = "period_configs"
        static let dressNotifs   = "dress_notifications_enabled"
        static let liveActivity  = "live_activity_enabled"
    }
}
