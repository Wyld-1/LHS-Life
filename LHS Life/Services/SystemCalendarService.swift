//
//  SystemCalendarService.swift
//  LHS Life
//
//  Writes a single event to a dedicated "LHS Life" calendar in the user's
//  Apple Calendar — ONLY on explicit user request (the "Save to Calendar"
//  button on EventDetailSheet). Never automatic, never triggered from a
//  background refresh — that distinction is the whole reason this exists
//  as a separate, deliberate action instead of the earlier auto-sync
//  approach.
//

import Foundation
import EventKit
import Observation

@MainActor
@Observable
final class SystemCalendarService {
    static let shared = SystemCalendarService()

    private let ekStore = EKEventStore()
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private static let calendarIdentifierKey = "lhs_life_calendar_identifier"
    private static let defaultCalendarTitle  = "LHS Life"
    private static let defaults = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    func requestAccess() async -> Bool {
        do {
            let granted = try await ekStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            return false
        }
    }

    enum SaveResult {
        case success
        case denied
        case failed
    }

    /// Saves the given detail item as a single event to a dedicated "LHS Life"
    /// calendar. Requests access first if not already determined — safe here
    /// specifically because this only ever runs from an explicit button tap.
    @discardableResult
    func save(_ item: EventDetailItem) async -> SaveResult {
        if authorizationStatus == .notDetermined {
            _ = await requestAccess()
        }
        guard isAuthorized else { return .denied }

        do {
            let calendar = try targetCalendar()
            let event = EKEvent(eventStore: ekStore)
            event.title    = item.title
            event.location = item.location
            event.notes    = item.description
            event.calendar = calendar
            event.isAllDay = item.isAllDay
            event.startDate = item.startDate
            event.endDate    = item.endDate

            try ekStore.save(event, span: .thisEvent)
            return .success
        } catch {
            print("[SystemCalendarService] Failed to save event: \(error)")
            return .failed
        }
    }

    // MARK: - Dedicated Calendar
    // Same pattern as RemindersService's Homework list — a dedicated
    // calendar so writes are clearly identifiable and don't clutter the
    // user's personal default calendar.

    private func targetCalendar() throws -> EKCalendar {
        if let id = Self.defaults.string(forKey: Self.calendarIdentifierKey),
           let cal = ekStore.calendar(withIdentifier: id),
           cal.allowsContentModifications {
            return cal
        }
        if let existing = ekStore.calendars(for: .event)
            .first(where: { $0.title == Self.defaultCalendarTitle }) {
            Self.defaults.set(existing.calendarIdentifier, forKey: Self.calendarIdentifierKey)
            return existing
        }
        let newCal = EKCalendar(for: .event, eventStore: ekStore)
        newCal.title  = Self.defaultCalendarTitle
        newCal.source = ekStore.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? ekStore.sources.first { $0.sourceType == .local }
        try ekStore.saveCalendar(newCal, commit: true)
        Self.defaults.set(newCal.calendarIdentifier, forKey: Self.calendarIdentifierKey)
        return newCal
    }
}
