//
//  LHSAppShortcuts.swift
//  LHS Life
//
//  Registers Tier 1 App Shortcuts. Every phrase must include
//  \(.applicationName) — Siri uses it to disambiguate which of a user's
//  apps should handle the request; this is compiler-permitted but silently
//  fails at runtime without it. "LaSalle" is registered as an alternate
//  app name in Info.plist (INAlternativeAppNames), so it's also spoken
//  wherever \(.applicationName) appears below.
//

import AppIntents

struct LHSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextClassIntent(),
            phrases: [
                "What's my next class in \(.applicationName)",
                "What class is next in \(.applicationName)",
                "When's my next class in \(.applicationName)"
            ],
            shortTitle: "Next Class",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: NextBellIntent(),
            phrases: [
                "When's the next bell in \(.applicationName)",
                "How much time is left in class in \(.applicationName)",
                "How much time is left, \(.applicationName)"
            ],
            shortTitle: "Next Bell",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: TodayScheduleIntent(),
            phrases: [
                "What schedule is today in \(.applicationName)",
                "Is today a block schedule in \(.applicationName)",
                "What's today's schedule in \(.applicationName)"
            ],
            shortTitle: "Today's Schedule",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: EveningEventsIntent(),
            phrases: [
                "What's happening this evening in \(.applicationName)",
                "What's going on tonight in \(.applicationName)",
                "Ask \(.applicationName) what's happening this evening"
            ],
            shortTitle: "Tonight at LaSalle",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: NextProfessionalDressDayIntent(),
            phrases: [
                "When's the next professional dress day in \(.applicationName)",
                "When's the next dress up day in \(.applicationName)"
            ],
            shortTitle: "Dress Day",
            systemImageName: "tshirt"
        )
        AppShortcut(
            intent: OpenLunchIntent(),
            phrases: [
                "Order lunch in \(.applicationName)",
                "Order lunch, \(.applicationName)"
            ],
            shortTitle: "Order Lunch",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: OpenGradesIntent(),
            phrases: [
                "Check my grades in \(.applicationName)",
                "Open my grades in \(.applicationName)"
            ],
            shortTitle: "Grades",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: OpenSchoologyIntent(),
            phrases: [
                "Open Schoology in \(.applicationName)"
            ],
            shortTitle: "Schoology",
            systemImageName: "laptopcomputer"
        )
        AppShortcut(
            intent: OpenHomeworkIntent(),
            phrases: [
                "Open homework in \(.applicationName)",
                "Show my homework in \(.applicationName)"
            ],
            shortTitle: "Homework",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: AddHomeworkIntent(),
            phrases: [
                "Add homework in \(.applicationName)",
                "Add an assignment in \(.applicationName)"
            ],
            shortTitle: "Add Homework",
            systemImageName: "plus.circle"
        )
    }
}
