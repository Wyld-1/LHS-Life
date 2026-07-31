//
//  NavigationIntents.swift
//  LHS Life
//
//  Tier 2 — foreground-and-navigate intents. Each just sets the pending
//  tab on AppNavigationCoordinator and opens the app; AppTabContainer
//  does the actual switch. No dialog/snippet needed — the app becoming
//  visible IS the response.
//

import AppIntents

struct OpenLunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Order Lunch"
    static let description = IntentDescription("Opens the Lunch ordering tab in LHS Life.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationCoordinator.shared.pendingTab = .lunch
        return .result()
    }
}

struct OpenGradesIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Grades"
    static let description = IntentDescription("Opens the Grades (PowerSchool) tab in LHS Life.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationCoordinator.shared.pendingTab = .powerschool
        return .result()
    }
}

struct OpenSchoologyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Schoology"
    static let description = IntentDescription("Opens the Schoology tab in LHS Life.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationCoordinator.shared.pendingTab = .schoology
        return .result()
    }
}

struct OpenHomeworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Homework"
    static let description = IntentDescription("Opens the Homework list in LHS Life.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationCoordinator.shared.pendingTab = .homework
        return .result()
    }
}
