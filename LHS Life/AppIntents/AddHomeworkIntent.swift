//
//  AddHomeworkIntent.swift
//  LHS Life
//
//  Tier 3 — the first write intent. Writes straight into the same
//  Reminders list RemindersService already maintains in-app, so anything
//  added via Siri shows up in the Homework tab immediately.
//
//  Reads RemindersService.shared directly rather than via @Dependency —
//  see NextClassIntent.swift header comment for why.
//
//  NOTE: requestConfirmation() usage here is the least-verified API call
//  in this whole batch — I have Apple's WWDC22/26 session transcripts
//  describing the pattern (confirm before a real side effect happens),
//  but haven't seen the exact current signature compile. If Xcode
//  disagrees, check autocomplete on `requestConfirmation` — the shape
//  may need adjusting, the confirm-before-mutating structure should not.
//

import AppIntents

struct AddHomeworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Homework"
    static let description = IntentDescription("Adds a homework assignment to your Homework reminders list.")

    @Parameter(title: "Assignment") var assignmentTitle: String
    @Parameter(title: "Class") var className: String?
    @Parameter(title: "Due Date") var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$assignmentTitle) for \(\.$className), due \(\.$dueDate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reminders = RemindersService.shared
        guard reminders.isAuthorized else {
            return .result(dialog: "LHS Life doesn't have access to Reminders yet — open the app once to grant access.")
        }

        var confirmText = "Add \"\(assignmentTitle)\""
        if let className, !className.isEmpty { confirmText += " for \(className)" }
        if let dueDate {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"
            confirmText += ", due \(f.string(from: dueDate))"
        }
        confirmText += "?"
        try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: confirmText)))

        try await reminders.addAssignment(title: assignmentTitle, className: className, dueDate: dueDate)
        return .result(dialog: "Added \"\(assignmentTitle)\" to your homework list.")
    }
}
