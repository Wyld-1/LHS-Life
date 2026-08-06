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
    /// The last real (non-zero) graduation year this account had. Kept so
    /// flipping to "Not a student" and back doesn't lose the year the user
    /// already typed. Never used for scheduling or eligibility — read only
    /// when prefilling the editor.
    var lastGraduationYear: Int
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

    // MARK: - Map

    /// Whether the Map tab is visible in the tab bar.
    /// Defaults to true for freshmen (graduation year == current year + 4),
    /// false for all other grade levels. User can override in Settings.
    var showMapTab: Bool
    
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
        
        // 0 is a real, meaningful value here — "not a student" (staff,
        // parents). Distinguish it from "never written" by key presence, the
        // same way showMapTab does below. Coercing 0 to the default used to
        // silently promote every staff account to the current senior class
        // on its second launch.
        //
        // Resolved into a local first: init can't read back self.graduationYear
        // to seed lastGraduationYear below until every stored property is
        // assigned, and periodConfigs and friends aren't set yet.
        let resolvedGradYear: Int
        if d.object(forKey: Keys.gradYear) != nil {
            resolvedGradYear = d.integer(forKey: Keys.gradYear)
        } else {
            resolvedGradYear = Self.defaultGradYear
        }
        self.graduationYear = resolvedGradYear
        
        // Seed from the resolved value for accounts that predate this key, so
        // an existing student who taps "Not a student" today still gets
        // their year back rather than an empty field.
        let storedLastYear = d.integer(forKey: Keys.lastGradYear)
        self.lastGraduationYear = storedLastYear != 0 ? storedLastYear : resolvedGradYear

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

        // Map tab — if never stored, default to true for freshmen
        if d.object(forKey: Keys.showMapTab) != nil {
            self.showMapTab = d.bool(forKey: Keys.showMapTab)
        } else {
            // Freshmen: grad year == current year + 4 (Aug or later bumps by 1)
            let cal = Calendar.current
            let now = Date()
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            let currentSeniorYear = month >= 8 ? year + 1 : year
            let storedYear = d.integer(forKey: Keys.gradYear)
            self.showMapTab = storedYear == currentSeniorYear + 4
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

    /// False for staff and parents — no graduation year, so no grade level,
    /// no Pathways eligibility, no grade-specific orientation window.
    /// Stored as graduationYear == 0; nothing should compare to 0 directly.
    var isStudent: Bool { graduationYear != 0 }

    /// Sets the graduation year, remembering the last real value. Always use
    /// this rather than assigning `graduationYear` directly — assigning 0
    /// straight would drop the year with no way to restore it.
    func setGraduationYear(_ year: Int) {
        graduationYear = year
        if year != 0 { lastGraduationYear = year }
    }

    /// What to prefill the grad-year editor with: the live year for a
    /// student, otherwise the last one they had. 0 if they never set one.
    var prefillGraduationYear: Int { isStudent ? graduationYear : lastGraduationYear }

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
        store.set(lastGraduationYear, forKey: Keys.lastGradYear)
        store.set(professionalDressNotificationsEnabled, forKey: Keys.dressNotifs)
        store.set(liveActivityMode.rawValue, forKey: Keys.liveActivityMode)
        store.set(isASBMember, forKey: Keys.asbMember)
        store.set(showMapTab, forKey: Keys.showMapTab)
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
    
    // MARK: - Sign Out / Reset

    /// Light reset — clears identity (email, grad year) and returns to the
    /// sign-in/lock screen. Deliberately keeps device-level customization
    /// (period colors, ASB settings, Live Activity mode, Pro Dress
    /// notifications) since this reads as "redo sign-in," not "reset the app."
    func signOut() {
        schoolEmail = ""
        graduationYear = Self.defaultGradYear
        lastGraduationYear = 0
        accessApproved = false
        save()
    }

    /// Full reset — wipes everything this app has stored, local and iCloud,
    /// and returns to the sign-in/lock screen. Deliberately does NOT touch
    /// anything written to the system Calendar or Reminders (Homework list,
    /// Class Orientation Day, any "Save to Calendar" events) — those live in
    /// the user's own Calendar/Reminders app, not in this settings store, and
    /// silently deleting a student's own saved reminders/events would be a
    /// much bigger, more surprising action than "reset my LHS Life profile."
    func deleteAllData() {
        hasCompletedOnboarding = false
        accessApproved = false
        schoolEmail = ""
        graduationYear = Self.defaultGradYear
        lastGraduationYear = 0
        periodConfigs = PeriodConfig.defaults
        professionalDressNotificationsEnabled = true
        liveActivityMode = .off
        liveActivityEnabledToday = false
        isASBMember = false
        asbWorkDays = Array(repeating: .off, count: 5)
        showMapTab = false
        apModeEnabledToday = false
        apBadgeCleared = false
        save()
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
        static let lastGradYear         = "last_graduation_year"
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
        static let showMapTab           = "show_map_tab"
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
        
        // Key presence, not a zero check — 0 means "not a student" and has
        // to sync like any other value, or a staff member's setting silently
        // fails to reach their iPad.
        if icloud.object(forKey: ICloudKeys.gradYear) != nil {
            let remoteYear = Int(icloud.longLong(forKey: ICloudKeys.gradYear))
            if remoteYear != graduationYear {
                graduationYear = remoteYear
                changed = true
            }
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
