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

@MainActor
@Observable
final class CalendarStore {

    // MARK: - State
    // No @Published needed — @Observable tracks all stored properties automatically.

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
    // settings is passed in but not stored as @Observable dependency —
    // ScheduleEngine reads it at call time, no observation chain needed here.
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
        if let cached = cache.loadEvents() {
            applyEvents(cached)
        }
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
        } catch {
            self.error = AppError(underlying: error)
        }
        isLoading = false
    }

    // MARK: - Queries

    func events(on dayKey: String) -> [SchoolEvent] {
        events.filter { $0.dayKey == dayKey }.sorted { $0.startDate < $1.startDate }
    }

    func bellSchedule(for dayKey: String) -> BellSchedule? {
        bellSchedules[dayKey]
    }

    func events(year: Int, month: Int) -> [SchoolEvent] {
        events.filter {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.startDate)
            return comps.year == year && comps.month == month
        }
    }

    /// Memoized today state. The expensive scan only runs once per calendar day
    /// or when events are refreshed. The 1-second header timer pays near-zero cost.
    func todayState(at date: Date = Date()) -> ScheduleEngine.ScheduleState {
        let dayKey = DateFormatter.isoDay.string(from: date)

        if dayKey != cachedTodayKey {
            // New day or first call — compute and cache the flags
            cachedTodayIsHoliday  = events.contains { $0.dayKey == dayKey && $0.category == .holiday }
            cachedTodayIsPathways = PathwaysService.isPathwaysDay(
                on: dayKey, events: events, graduationYear: settings.graduationYear
            )
            cachedTodayKey = dayKey
        }

        return ScheduleEngine.state(
            for: date,
            schedule: bellSchedules[dayKey],
            settings: settings,
            isPathwaysDay: cachedTodayIsPathways,
            isHoliday: cachedTodayIsHoliday
        )
    }

    // MARK: - Private

    private func applyEvents(_ fetched: [SchoolEvent]) {
        events = fetched.sorted { $0.startDate < $1.startDate }
        var schedules: [String: BellSchedule] = [:]
        for event in events where event.hasBellSchedule {
            if let schedule = bellParser.parse(from: event) {
                schedules[schedule.dayKey] = schedule
            }
        }
        bellSchedules = schedules
        cachedTodayKey = ""  // bust cache on fresh data
        SharedStore.write(events: events, bellSchedules: bellSchedules)
    }
}

// MARK: - AppError

struct AppError: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}
