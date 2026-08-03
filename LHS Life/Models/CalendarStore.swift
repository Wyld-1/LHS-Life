//
//  CalendarStore.swift
//  LaSalle Schedule
//
//  @Observable replaces ObservableObject + @Published.
//  SwiftUI now re-renders ONLY views that read the specific property that changed.
//  The header timer ticking never causes EventsTabView or LunchTabView to re-render.
//

import Foundation
import Observation
import SwiftUI

// MARK: - CalendarUIState

enum CalendarViewMode { case day, month, year }

@MainActor
@Observable
final class CalendarUIState {
    var viewMode: CalendarViewMode = .day
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    var scrollToNow: Bool = false
    var scrollToEvent: SchoolEvent? = nil

    // MARK: - Stale-date correction
    //
    // When the app foregrounds after being backgrounded for more than two hours,
    // snap selectedDate to today if it's from a previous calendar day. This
    // covers the "picked up phone the next morning" case without interrupting
    // someone who backgrounds briefly during a class to check a message.
    //
    // Two hours: long enough to survive a class period, short enough that
    // you'll never wake up to yesterday.
    //
    // View mode is intentionally left alone — if they were in Month view,
    // they stay in Month view. Only the selected date resets.
    private var backgroundedAt: Date? = nil
    private let staleThreshold: TimeInterval = 2 * 60 * 60  // 2 hours

    func appDidBackground() {
        backgroundedAt = Date()
    }

    func appDidForeground() {
        guard let backgroundedAt,
              Date().timeIntervalSince(backgroundedAt) >= staleThreshold
        else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard !Calendar.current.isDate(selectedDate, inSameDayAs: today) else { return }
        selectedDate = today
        self.backgroundedAt = nil
    }

    func navigateTo(event: SchoolEvent) {
        selectedDate = Calendar.current.startOfDay(for: event.startDate)
        scrollToEvent = nil  // reset first so onChange fires even for the same event
        withAnimation(.lsSnappy) { viewMode = .day }
        // Brief delay so nil propagates before setting the new value
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            scrollToEvent = event
        }
    }
    private let cal = Calendar.current

    func goToToday() {
        selectedDate = cal.startOfDay(for: Date())
        scrollToNow.toggle()  // toggle so repeated taps always fire
        withAnimation(.lsSnappy) { viewMode = .day }
    }
    func zoomOut() {
        withAnimation(.lsSnappy) {
            switch viewMode {
            case .day:   viewMode = .month
            case .month: viewMode = .year
            case .year:  break
            }
        }
    }
    func zoomIn(to date: Date) {
        selectedDate = cal.startOfDay(for: date)
        withAnimation(.lsSnappy) {
            switch viewMode {
            case .year:  viewMode = .month
            case .month: viewMode = .day
            case .day:   break
            }
        }
    }
    var zoomOutLabel: String? {
        switch viewMode {
        case .day:   return "Month"
        case .month: return "Year"
        case .year:  return "Day"
        }
    }
    var zoomOutAction: () -> Void {
        switch viewMode {
        case .day, .month: return { self.zoomOut() }
        case .year:        return { withAnimation(.lsSnappy) { self.viewMode = .day } }
        }
    }
}

// MARK: - CalendarStore

@MainActor
@Observable
final class CalendarStore {

    // Single shared instance so the UI and App Intents (Siri/Shortcuts) always
    // read the exact same live data — no AppDependencyManager registration,
    // no timing race on background-launched intents. Same pattern UserSettings
    // already used.
    static let shared = CalendarStore()

    // MARK: - State
    private(set) var events: [SchoolEvent] = []
    private(set) var bellSchedules: [String: BellSchedule] = [:]
    private(set) var isLoading: Bool = false
    private(set) var lastFetched: Date? = nil
    private(set) var error: AppError? = nil

    // MARK: - Memoized today state
    private var cachedTodayKey: String = ""
    private var cachedTodayIsHoliday: Bool = false
    private var cachedTodayIsPathways: Bool = false

    // MARK: - Dependencies
    private let iCalService: ICalService
    private let bellParser: BellScheduleParser
    private let cache: CacheService
    private let settings: UserSettings

    // MARK: - Init
    init(
        iCalService: ICalService = ICalService(),
        bellParser: BellScheduleParser = BellScheduleParser(),
        cache: CacheService = CacheService(),
        settings: UserSettings = .shared
    ) {
        self.iCalService = iCalService
        self.bellParser  = bellParser
        self.cache       = cache
        self.settings    = settings
    }

    // MARK: - Public API
    func loadAll() async {
        if let cached = cache.loadEvents() { applyEvents(cached) }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        error = nil
        do {
            let fetched = try await iCalService.fetchEvents()
            cache.saveEvents(fetched)
            applyEvents(fetched)
            lastFetched = Date()
            if settings.professionalDressNotificationsEnabled {
                await NotificationService.scheduleProfessionalDressNotifications(for: fetched)
            }
            if settings.isASBMember {
                await NotificationService.scheduleASBNotifications(settings: settings, store: self)
            }
            await NotificationService.scheduleAbnormalScheduleNotifications(settings: settings, store: self)
            await NotificationService.scheduleLiveActivityReminderNotifications(settings: settings, store: self)
            await NotificationService.scheduleClassOrientationNotification(events: fetched, settings: settings)
        } catch {
            self.error = AppError(underlying: error)
        }
        isLoading = false
    }

    // MARK: - Queries
    func events(on dayKey: String) -> [SchoolEvent] {
        events.filter { $0.dayKey == dayKey }.sorted { $0.startDate < $1.startDate }
    }
    func bellSchedule(for dayKey: String) -> BellSchedule? { bellSchedules[dayKey] }

    func summary(for dayKey: String) -> DaySummary {
        let schedule = bellSchedules[dayKey]
        let dayEvents = events(on: dayKey)
        let cats = Set(dayEvents.filter { !$0.isAllDay && $0.category != .schedules }.map { $0.category })
        return DaySummary(scheduleType: schedule?.scheduleType, eventCategories: cats)
    }

    func events(year: Int, month: Int) -> [SchoolEvent] {
        events.filter {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.startDate)
            return comps.year == year && comps.month == month
        }
    }

    /// Debug-only (screenshot tool). Injects a synthetic "Regular Schedule"
    /// for the given date using the app's own existing regular-period
    /// generator — the same one already used as the Pro Dress "floor rule"
    /// fallback — so screenshots can show a normal school day even when no
    /// real bell-schedule data is loaded for that date (e.g. over summer).
    func debugInjectRegularSchedule(for date: Date) {
        let dayKey = DateFormatter.isoDay.string(from: date)
        bellSchedules[dayKey] = BellSchedule(
            id: "debug-regular-\(dayKey)",
            date: date,
            scheduleType: .regular,
            periods: FinalExamParser.regularPeriods(for: date, sourceID: "debug"),
            sourceEventID: "debug"
        )
        cachedTodayKey = ""  // force todayState to recompute against the new schedule
    }

    func todayState(at date: Date = Date()) -> ScheduleEngine.ScheduleState {
        let dayKey = DateFormatter.isoDay.string(from: date)
        if dayKey != cachedTodayKey {
            cachedTodayIsHoliday  = events.contains { $0.dayKey == dayKey && $0.isHoliday }
            cachedTodayIsPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: events, graduationYear: settings.graduationYear
            )
            cachedTodayKey = dayKey
        }
        let scheduleForDay = bellSchedules[dayKey]
        return ScheduleEngine.state(
            for: date,
            schedule: scheduleForDay,
            settings: settings,
            isPathwaysDay: cachedTodayIsPathways,
            isHoliday: cachedTodayIsHoliday
        )
    }

    // MARK: - Private
    private func applyEvents(_ fetched: [SchoolEvent]) {
        // Personalizes "Class Orientation Day" to the student's grade-specific
        // time window before anything else touches the array — same UID, so
        // tap-to-detail and the notification both resolve to the same event.
        let personalized = ClassOrientationService.personalize(events: fetched, graduationYear: settings.graduationYear)
        events = personalized.sorted { $0.startDate < $1.startDate }
        var schedules: [String: BellSchedule] = [:]

        for event in events where event.hasBellSchedule {
            let parsed = bellParser.parse(from: event, graduationYear: settings.graduationYear)
            for schedule in parsed {
                if let existing = schedules[schedule.dayKey] {
                    // High-priority schedules (finals, seniorPresentation) are never
                    // overwritten by lower-priority ones. Pro Dress Day embeds a regular
                    // schedule table in its description and would otherwise clobber these.
                    let existingIsProtected = existing.scheduleType == .finals
                        || existing.scheduleType == .seniorPresentation
                    let incomingIsHigher = schedule.scheduleType == .finals
                        || schedule.scheduleType == .seniorPresentation
                    if existingIsProtected && !incomingIsHigher { continue }
                }
                schedules[schedule.dayKey] = schedule
            }
        }
        // Post-processing: bare schedule-marker floor rule. Runs BEFORE the
        // Pro Dress floor rule below on purpose — a day can have both a Pro
        // Dress event AND a specific schedule marker (e.g. "Odd Block
        // Schedule", or the Mass of the Holy Spirit day, which is itself both
        // Pro Dress and an early-dismissal schedule day). The specific,
        // title-matched schedule should always win over Pro Dress's generic
        // "just assume Regular" fallback, not get overwritten by it.
        //
        // LaSalle's real feed confirms routine days carry a CATEGORIES:Schedules
        // marker event with NO description at all — only special days (Late
        // Start, Early Release, etc. that need explanation) get a real time
        // table. Without this, hasBellSchedule correctly detects the day as a
        // schedule day but BellScheduleParser has nothing to parse, so the day
        // silently gets zero periods. Tries the three standard schedule types
        // in order, most-specific title match first — each guards against the
        // others' keywords so a genuinely different/special variant (anything
        // with "liturgy", or Regular Liturgy specifically) still falls through
        // to needing a real table rather than getting a guessed-wrong synthetic one.
        for event in fetched where event.hasBellSchedule {
            let dayKey = event.dayKey
            guard schedules[dayKey] == nil else { continue }
            let t = event.title.lowercased()
            guard !t.contains("liturgy") else { continue }

            let periods: [Period]?
            let scheduleType: ScheduleType?
            if t.contains("odd") && t.contains("block") {
                periods = FinalExamParser.oddBlockPeriods(for: event.startDate, sourceID: "floor")
                scheduleType = .oddBlock
            } else if t.contains("even") && t.contains("block") {
                periods = FinalExamParser.evenBlockPeriods(for: event.startDate, sourceID: "floor")
                scheduleType = .evenBlock
            } else if t.contains("regular") && !t.contains("block") && !t.contains("early") && !t.contains("late") {
                periods = FinalExamParser.regularPeriods(for: event.startDate, sourceID: "floor")
                scheduleType = .regular
            } else {
                periods = nil
                scheduleType = nil
            }
            guard let periods, let scheduleType else { continue }

            let isPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: fetched, graduationYear: settings.graduationYear
            )
            guard !isPathways else { continue }
            schedules[dayKey] = BellSchedule(
                id: "\(scheduleType.rawValue)-floor-\(dayKey)",
                date: event.startDate,
                scheduleType: scheduleType,
                periods: periods,
                sourceEventID: "floor"
            )
        }

        // Post-processing: Pro Dress floor rule.
        // If a day has a Professional Dress event but still no schedule after
        // everything above (real parsing, and the specific-marker floor rule
        // just above), school is in session — apply a regular schedule as the
        // absolute last-resort floor. Exception: Pathways Day students have
        // no regular schedule.
        let proDressDays = fetched
            .filter { $0.isProfessionalDress }
            .map { DateFormatter.isoDay.string(from: $0.startDate) }
        for dayKey in proDressDays where schedules[dayKey] == nil {
            let isPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: fetched, graduationYear: settings.graduationYear
            )
            guard !isPathways else { continue }
            let date = fetched
                .first { DateFormatter.isoDay.string(from: $0.startDate) == dayKey }
                .map { $0.startDate } ?? Date()
            schedules[dayKey] = BellSchedule(
                id: "regular-\(dayKey)",
                date: date,
                scheduleType: .regular,
                periods: FinalExamParser.regularPeriods(for: date, sourceID: "floor"),
                sourceEventID: "floor"
            )
        }

        bellSchedules = schedules
        cachedTodayKey = ""
        SharedStore.write(events: events, bellSchedules: bellSchedules)
    }
}

// MARK: - DaySummary

struct DaySummary {
    let scheduleType: ScheduleType?
    let eventCategories: Set<EventCategory>
    var isEmpty: Bool { scheduleType == nil && eventCategories.isEmpty }
    var pillColors: [Color] {
        var colors: [Color] = []
        if let type = scheduleType { colors.append(type.pillColor) }
        for cat in eventCategories.sorted(by: { $0.rawValue < $1.rawValue }) { colors.append(cat.pillColor) }
        return colors
    }
}

extension ScheduleType {
    var pillColor: Color {
        switch self {
        case .regular:                                    return Color.lsTertiary
        case .regularLiturgy:                             return Color.lsBlue
        case .oddBlock, .evenBlock:                       return Color.lsBlue
        case .oddBlockLiturgy, .evenBlockLiturgy:         return Color.lsBlue
        case .lateStart:                                  return Color.lsOrange
        case .earlyRelease, .earlyReleaseLiturgy:         return Color.lsGold
        case .assembly:                                   return Color.lsSuccess
        case .seniorPresentation:                          return Color.lsGold
        case .finals:                                      return Color.lsDestructive
        case .custom, .unknown:                            return Color.lsSecondary
        }
    }
}

extension EventCategory {
    var pillColor: Color {
        switch self {
        // Tier 1 — vivid, distinct. Things students actually look for.
        case .academics:            return Color.lsGold
        case .athletics:             return Color.lsDestructive
        case .facultyStaff:         return Color.lsBlue
        case .campusMinistry:       return Color.lsPurple
        case .studentActivities:     return Color.lsOrange
        case .service:               return Color.lsSuccess
        case .visualPerformingArts:  return Color.lsRose
        case .counselingGuidance:   return Color.lsTeal
        // Tier 2 — shared muted neutral. Rare, admin-facing, students rarely
        // see these day-to-day.
        case .admissions, .advancementDevelopment, .alumni, .facilities, .parentAssociation:
            return Color.lsSecondary
        // Schedule metadata, not a real "thing happening" — stays hidden from
        // event surfaces entirely (see AllDayStrip/DayColumn filtering).
        case .schedules:              return Color.lsTertiary
        case .other:                 return Color.lsSecondary
        }
    }
}

// MARK: - AppError

struct AppError: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}
