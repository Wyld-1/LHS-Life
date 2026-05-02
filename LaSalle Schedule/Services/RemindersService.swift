//
//  RemindersService.swift
//  LaSalle Schedule
//
//  Wraps EventKit to create reminders in a "Homework" list,
//  organized into per-class sublists.
//

import Foundation
import EventKit
import Combine

@MainActor
final class RemindersService: ObservableObject {

    private let store = EKEventStore()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            return granted
        } catch {
            print("[RemindersService] Access request failed: \(error)")
            return false
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    // MARK: - Add Assignment

    func addAssignment(title: String, className: String, dueDate: Date?) async throws {
        guard isAuthorized else { throw RemindersError.notAuthorized }

        let list = try homeworkList(for: className)
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        reminder.notes = className

        if let due = dueDate {
            reminder.addAlarm(EKAlarm(absoluteDate: due))
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }

        try store.save(reminder, commit: true)
    }

    // MARK: - List Management

    /// Returns the reminder list for a class by name, creating it if needed.
    /// Synchronous — EventKit calendar operations don't need async.
    private func homeworkList(for className: String) throws -> EKCalendar {
        let title = className.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Homework"
            : className

        if let existing = store.calendars(for: .reminder).first(where: { $0.title == title }) {
            return existing
        }

        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = title
        newList.source = preferredSource()
        try store.saveCalendar(newList, commit: true)
        return newList
    }

    private func preferredSource() -> EKSource? {
        if let iCloud = store.sources.first(where: { $0.sourceType == .calDAV && $0.title == "iCloud" }) {
            return iCloud
        }
        if let local = store.sources.first(where: { $0.sourceType == .local }) {
            return local
        }
        return nil
    }
}

// MARK: - Errors

enum RemindersError: LocalizedError {
    case notAuthorized
    var errorDescription: String? {
        "Please allow LaSalle Schedule to access Reminders in Settings."
    }
}
