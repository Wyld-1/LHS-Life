//
//  RemindersService.swift
//  LHS Life
//
//  Creates and manages a single "Homework" list in Apple Reminders.
//  The list identifier is persisted so renaming by the user doesn't break the link.
//  Silently matches existing sections by class name (case-insensitive) for power users.
//  Class name is always written to reminder notes as a fallback.
//

import Foundation
import EventKit
import Observation
import Combine

@MainActor
final class RemindersService: ObservableObject {

    private let ekStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private static let listNameKey       = "homework_list_identifier"
    private static let defaultListTitle  = "Homework"
    private static let defaults          = UserDefaults(suiteName: UserSettings.appGroupID) ?? .standard

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        do {
            let granted = try await ekStore.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            return granted
        } catch {
            return false
        }
    }

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    // MARK: - Add Assignment

    /// Priority follows EKReminder convention: 0 = none, 1 = high, 5 = medium, 9 = low.
    func addAssignment(
        title: String,
        className: String?,
        dueDate: Date?,
        priority: Int = 0
    ) async throws {
        guard isAuthorized else { throw RemindersError.notAuthorized }

        let list = try homeworkList()
        let reminder = EKReminder(eventStore: ekStore)
        reminder.title    = title
        reminder.calendar = list
        reminder.notes    = className   // nil when no class selected — no notes written
        reminder.priority = priority

        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day], from: due
            )
        }

        try ekStore.save(reminder, commit: true)
    }

    // MARK: - Homework List

    /// Returns the persistent "Homework" reminder list, creating it if needed.
    /// Identified by stored calendarIdentifier so user can rename freely.
    private func homeworkList() throws -> EKCalendar {
        // 1. Look up by stored identifier
        if let id = Self.defaults.string(forKey: Self.listNameKey),
           let cal = ekStore.calendar(withIdentifier: id),
           cal.allowsContentModifications {
            return cal
        }
        // 2. Fall back to searching by title (handles first launch or deleted list)
        if let existing = ekStore.calendars(for: .reminder)
            .first(where: { $0.title.lowercased() == Self.defaultListTitle.lowercased() }) {
            Self.defaults.set(existing.calendarIdentifier, forKey: Self.listNameKey)
            return existing
        }
        // 3. Create a new list
        let newList    = EKCalendar(for: .reminder, eventStore: ekStore)
        newList.title  = Self.defaultListTitle
        newList.source = preferredSource()
        try ekStore.saveCalendar(newList, commit: true)
        Self.defaults.set(newList.calendarIdentifier, forKey: Self.listNameKey)
        return newList
    }

    private func preferredSource() -> EKSource? {
        ekStore.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? ekStore.sources.first { $0.sourceType == .local }
    }
}

// MARK: - Priority

/// Maps our UI labels to EKReminder priority integers.
enum ReminderPriority: Int, CaseIterable {
    case none   = 0
    case low    = 9
    case medium = 5
    case high   = 1

    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var exclamations: String {
        switch self {
        case .none:   return ""
        case .low:    return "!"
        case .medium: return "!!"
        case .high:   return "!!!"
        }
    }

    /// Cycles none → low → medium → high → none
    var next: ReminderPriority {
        switch self {
        case .none:   return .low
        case .low:    return .medium
        case .medium: return .high
        case .high:   return .none
        }
    }
}

// MARK: - Errors

enum RemindersError: LocalizedError {
    case notAuthorized
    var errorDescription: String? {
        "Allow LHS Life to access Reminders in Settings to save assignments."
    }
}
