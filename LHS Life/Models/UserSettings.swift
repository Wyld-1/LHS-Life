//
//  UserSettings.swift
//  LHS Life
//

import Foundation
import Observation
#if !WIDGET_EXTENSION
import Combine
#endif

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
    
    static let appGroupID = "group.lhslife.widgetinfo"
    @ObservationIgnored private let store: UserDefaults
    static let shared = UserSettings()
    
    // MARK: - State
    
    var hasCompletedOnboarding: Bool
    var accessApproved: Bool
    var graduationYear: Int
    var schoolEmail: String
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
    
    // MARK: - AP Exam
    
    /// dayKey for which the student has manually silenced notifications for an AP exam.
    @ObservationIgnored private var apSilencedKey: String = ""
    /// dayKey for which the settings badge has been cleared (user opened settings).
    @ObservationIgnored private var apBadgeClearedKey: String = ""
    
    var apModeEnabledToday: Bool {
        get { apSilencedKey == DateFormatter.isoDay.string(from: Date()) }
        set {
            let today = DateFormatter.isoDay.string(from: Date())
            apSilencedKey = newValue ? today : ""
            store.set(newValue ? today : "", forKey: Keys.apSilencedKey)
        }
    }
    
    var apBadgeCleared: Bool {
        get { apBadgeClearedKey == DateFormatter.isoDay.string(from: Date()) }
        set {
            let today = DateFormatter.isoDay.string(from: Date())
            apBadgeClearedKey = newValue ? today : ""
            store.set(newValue ? today : "", forKey: Keys.apBadgeClearedKey)
        }
    }
    
    /// True if AP Mode is on AND the user's base Live Activity setting allows it.
    func apModeActive(scheduleType: ScheduleType?) -> Bool {
        guard apModeEnabledToday else { return false }
        return liveActivityEffectivelyEnabled(scheduleType: scheduleType)
    }
    
    // MARK: - Init
    
    init() {
        let d = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard
        self.store = d
        
        self.hasCompletedOnboarding = d.bool(forKey: Keys.onboarding)
        self.accessApproved = d.bool(forKey: Keys.accessApproved)
        self.schoolEmail = d.string(forKey: Keys.schoolEmail) ?? ""
        
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
        
        // AP exam silencing — restore persisted dayKeys
        self.apSilencedKey     = d.string(forKey: Keys.apSilencedKey)     ?? ""
        self.apBadgeClearedKey = d.string(forKey: Keys.apBadgeClearedKey) ?? ""
    }
    
    // MARK: - Live Activity effective state
    
    /// True if Live Activities should run right now.
    /// Pass the current schedule type so .abnormalOnly can activate automatically.
    /// True when the user is in their graduating (senior) year.
    /// August or later = new school year has started, so senior class year increments.
    var isSenior: Bool {
        let cal   = Calendar.current
        let now   = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)
        let seniorGradYear = month >= 8 ? year + 1 : year
        return graduationYear == seniorGradYear
    }

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
            let abnormal: Set<ScheduleType> = [
                .lateStart, .earlyRelease, .earlyReleaseLiturgy,
                .oddBlock, .evenBlock, .oddBlockLiturgy, .evenBlockLiturgy,
                .assembly, .custom
            ]
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
        store.set(accessApproved, forKey: Keys.accessApproved)
        store.set(schoolEmail, forKey: Keys.schoolEmail)
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
#if !WIDGET_EXTENSION
        pushToICloud()
#endif
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
        let year  = comps.year ?? Calendar.current.component(.year, from: Date())
        let month = comps.month ?? 1
        return month >= 8 ? year + 1 : year
    }
    
    private enum Keys {
        static let onboarding           = "onboarding_complete"
        static let accessApproved        = "access_approved"
        static let schoolEmail           = "school_email"
        static let gradYear             = "graduation_year"
        static let periodConfigs        = "period_configs"
        static let dressNotifs          = "dress_notifications_enabled"
        static let liveActivityMode      = "live_activity_mode"
        static let abnormalNotifs        = "abnormal_schedule_notifications"  // legacy, unused
        static let liveActivityToday    = "live_activity_today"
        static let liveActivityTodayKey = "live_activity_today_key"
        static let apSilencedKey        = "ap_exam_silenced_key"
        static let apBadgeClearedKey    = "ap_badge_cleared_key"
        static let paletteVersion       = "palette_version"
        static let asbMember            = "asb_member"
        static let asbWorkDays          = "asb_work_days"
    }
    
    private static let currentPaletteVersion = 2
    
    // MARK: - iCloud KV Sync
    // Syncs user identity and preferences across iPhone and iPad on the same Apple ID.
    // One person should only have to set up their profile once.
    //
    // Synced:     periodConfigs, graduationYear, professionalDressNotificationsEnabled,
    //             isASBMember, asbWorkDays, apSilencedKey, apBadgeClearedKey,
    //             hasCompletedOnboarding, accessApproved, schoolEmail
    // Not synced: liveActivityMode, liveActivityEnabledToday (per-device preference)
    
#if !WIDGET_EXTENSION
    @ObservationIgnored private var iCloudObserver: AnyCancellable?
    
    func startICloudSync() {
        // Pull remote changes on launch
        mergeFromICloud()
        NSUbiquitousKeyValueStore.default.synchronize()
        
        // Observe changes pushed from other devices
        iCloudObserver = NotificationCenter.default
            .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mergeFromICloud()
            }
    }
    
    /// Writes syncable prefs to iCloud KV. Called from save().
    private func pushToICloud() {
        let icloud = NSUbiquitousKeyValueStore.default
        icloud.set(Int64(graduationYear), forKey: ICloudKeys.gradYear)
        icloud.set(professionalDressNotificationsEnabled, forKey: ICloudKeys.dressNotifs)
        icloud.set(isASBMember, forKey: ICloudKeys.asbMember)
        icloud.set(hasCompletedOnboarding, forKey: ICloudKeys.onboarding)
        icloud.set(accessApproved, forKey: ICloudKeys.accessApproved)
        icloud.set(schoolEmail, forKey: ICloudKeys.schoolEmail)
        icloud.set(apSilencedKey, forKey: ICloudKeys.apSilencedKey)
        icloud.set(apBadgeClearedKey, forKey: ICloudKeys.apBadgeClearedKey)
        if let data = try? JSONEncoder().encode(periodConfigs) {
            icloud.set(data, forKey: ICloudKeys.periodConfigs)
        }
        if let data = try? JSONEncoder().encode(asbWorkDays) {
            icloud.set(data, forKey: ICloudKeys.asbWorkDays)
        }
        icloud.synchronize()
    }
    
    /// Reads remote iCloud values and merges them in. Last-write-wins (iCloud's default).
    /// Writes merged state back to App Group UserDefaults via save() so the widget
    /// picks up the changes immediately.
    private func mergeFromICloud() {
        let icloud = NSUbiquitousKeyValueStore.default
        var changed = false
        
        let remoteYear = Int(icloud.longLong(forKey: ICloudKeys.gradYear))
        if remoteYear != 0, remoteYear != graduationYear {
            graduationYear = remoteYear
            changed = true
        }
        
        let remoteDress = icloud.object(forKey: ICloudKeys.dressNotifs) as? Bool
        if let remoteDress, remoteDress != professionalDressNotificationsEnabled {
            professionalDressNotificationsEnabled = remoteDress
            changed = true
        }
        
        let remoteASB = icloud.object(forKey: ICloudKeys.asbMember) as? Bool
        if let remoteASB, remoteASB != isASBMember {
            isASBMember = remoteASB
            changed = true
        }
        
        let remoteOnboarding = icloud.object(forKey: ICloudKeys.onboarding) as? Bool
        if let remoteOnboarding, remoteOnboarding != hasCompletedOnboarding {
            hasCompletedOnboarding = remoteOnboarding
            changed = true
        }
        
        let remoteAccess = icloud.object(forKey: ICloudKeys.accessApproved) as? Bool
        if let remoteAccess, remoteAccess != accessApproved {
            accessApproved = remoteAccess
            changed = true
        }
        
        let remoteEmail = icloud.string(forKey: ICloudKeys.schoolEmail) ?? ""
        if !remoteEmail.isEmpty, remoteEmail != schoolEmail {
            schoolEmail = remoteEmail
            changed = true
        }
        
        let remoteAPSilenced = icloud.string(forKey: ICloudKeys.apSilencedKey) ?? ""
        if !remoteAPSilenced.isEmpty, remoteAPSilenced != apSilencedKey {
            apSilencedKey = remoteAPSilenced
            changed = true
        }
        
        let remoteAPBadge = icloud.string(forKey: ICloudKeys.apBadgeClearedKey) ?? ""
        if !remoteAPBadge.isEmpty, remoteAPBadge != apBadgeClearedKey {
            apBadgeClearedKey = remoteAPBadge
            changed = true
        }
        
        if let data = icloud.data(forKey: ICloudKeys.periodConfigs),
           let remote = try? JSONDecoder().decode([PeriodConfig].self, from: data),
           remote != periodConfigs {
            periodConfigs = remote
            changed = true
        }
        
        if let data = icloud.data(forKey: ICloudKeys.asbWorkDays),
           let remote = try? JSONDecoder().decode([ASBDayMode].self, from: data),
           remote.count == 5, remote != asbWorkDays {
            asbWorkDays = remote
            changed = true
        }
        
        // Persist merged state to App Group so widget reflects remote changes
        if changed { save() }
    }
#endif
    
    private enum ICloudKeys {
        static let gradYear          = "icloud_graduation_year"
        static let dressNotifs       = "icloud_dress_notifications_enabled"
        static let asbMember         = "icloud_asb_member"
        static let onboarding        = "icloud_onboarding_complete"
        static let accessApproved    = "icloud_access_approved"
        static let schoolEmail       = "icloud_school_email"
        static let apSilencedKey     = "icloud_ap_silenced_key"
        static let apBadgeClearedKey = "icloud_ap_badge_cleared_key"
        static let periodConfigs     = "icloud_period_configs"
        static let asbWorkDays       = "icloud_asb_work_days"
    }
}
