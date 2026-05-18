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
        let cats = Set(dayEvents.filter { !$0.isAllDay && $0.category != .bellSchedule }.map { $0.category })
        return DaySummary(scheduleType: schedule?.scheduleType, eventCategories: cats)
    }

    func events(year: Int, month: Int) -> [SchoolEvent] {
        events.filter {
            let comps = Calendar.current.dateComponents([.year, .month], from: $0.startDate)
            return comps.year == year && comps.month == month
        }
    }

    func todayState(at date: Date = Date()) -> ScheduleEngine.ScheduleState {
        let dayKey = DateFormatter.isoDay.string(from: date)
        if dayKey != cachedTodayKey {
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
            for schedule in bellParser.parse(from: event, graduationYear: settings.graduationYear) {
                if let existing = schedules[schedule.dayKey],
                   existing.scheduleType == .finals,
                   schedule.scheduleType != .finals { continue }
                schedules[schedule.dayKey] = schedule
            }
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
        case .regular:          return Color.lsTertiary
        case .block:            return Color.lsBlue
        case .lateStart:        return Color.lsOrange
        case .earlyRelease:     return Color.lsGold
        case .assembly:         return Color.lsSuccess
        case .finals:           return Color.lsDestructive
        case .custom, .unknown: return Color.lsSecondary
        }
    }
}

extension EventCategory {
    var pillColor: Color {
        switch self {
        case .bellSchedule: return Color.lsTertiary
        case .athletic:     return Color.lsGold
        case .academic:     return Color.lsSuccess
        case .liturgy:      return Color.lsBlue
        case .holiday:      return Color.lsOrange
        case .other:        return Color.lsSecondary
        }
    }
}

// MARK: - AppError

struct AppError: LocalizedError {
    let underlying: Error
    var errorDescription: String? { underlying.localizedDescription }
}
