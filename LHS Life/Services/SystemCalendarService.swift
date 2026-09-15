//
//  SystemCalendarService.swift
//  LHS Life
//
//  Writes a single event to the user's default Apple Calendar — ONLY on
//  explicit user request (the "Save to Calendar"
//  button on EventDetailSheet). Never automatic, never triggered from a
//  background refresh — that distinction is the whole reason this exists
//  as a separate, deliberate action instead of the earlier auto-sync
//  approach.
//
//  Write-only access, not full access. Full access would let the app read
//  every event on a student's calendar just to add one school event; write-
//  only can add events and nothing else. The cost is the old dedicated
//  "LHS Life" calendar: finding or creating a calendar needs read access, so
//  events now go to the default calendar for new events. Anyone who already
//  has an "LHS Life" calendar from an earlier version keeps it and its events.
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

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Either level can write. .fullAccess only shows up for someone who
    /// granted it to an earlier version.
    var isAuthorized: Bool { authorizationStatus == .writeOnly || authorizationStatus == .fullAccess }

    func requestAccess() async -> Bool {
        do {
            let granted = try await ekStore.requestWriteOnlyAccessToEvents()
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

    /// Saves the given detail item as a single event to the default calendar.
    /// Requests access first if not already determined — safe here
    /// specifically because this only ever runs from an explicit button tap.
    @discardableResult
    func save(_ item: EventDetailItem) async -> SaveResult {
        if authorizationStatus == .notDetermined {
            _ = await requestAccess()
        }
        guard isAuthorized else { return .denied }

        do {
            let event = EKEvent(eventStore: ekStore)
            event.title    = item.title
            event.location = item.location
            event.notes    = item.description
            event.calendar = ekStore.defaultCalendarForNewEvents
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
}
