//
//  HomeworkSheet.swift
//  LHS Life
//
//  Quick-add homework sheet. Opens from the FAB (legacy) or the
//  checklist tab (iOS 26). Auto-selects the current period's class.
//  Adds a reminder to the class's list in Apple Reminders.
//

import SwiftUI
import EventKit

struct HomeworkSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @StateObject private var reminders = RemindersService()

    // The assignment being composed
    @State private var title       = ""
    @State private var selectedPeriodID: Int
    @State private var dueDate: Date? = nil
    @State private var showDatePicker = false
    @State private var isSaving = false
    @State private var error: String? = nil

    @FocusState private var titleFocused: Bool

    init() {
        // Default to the current period, or period 1 if school isn't in session
        let currentPeriodID = HomeworkSheet.currentPeriodID()
        _selectedPeriodID = State(initialValue: currentPeriodID)
    }

    private static func currentPeriodID() -> Int {
        // Will be wired to ScheduleEngine once we have access to store in init.
        // For now default to 1 — overridden in onAppear.
        return 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("Add Assignment")
                    .font(.lsTitle)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.lsBody)
                    .foregroundStyle(Color.lsSecondary)
            }
            .padding(.horizontal, LS.md)
            .padding(.top, LS.lg)
            .padding(.bottom, LS.md)

            Divider().background(Color.lsTertiary.opacity(0.3))

            ScrollView {
                VStack(spacing: LS.lg) {

                    // MARK: Assignment title
                    VStack(alignment: .leading, spacing: LS.sm) {
                        sectionLabel("Assignment")
                        TextField("e.g. Chapter 4 reading", text: $title)
                            .font(.lsBody)
                            .foregroundStyle(Color.lsPrimary)
                            .padding(LS.md)
                            .lsCard()
                            .focused($titleFocused)
                            .submitLabel(.done)
                    }

                    // MARK: Class picker
                    VStack(alignment: .leading, spacing: LS.sm) {
                        sectionLabel("Class")
                        VStack(spacing: 0) {
                            ForEach(settings.periodConfigs.filter { $0.isEnabled }) { config in
                                Button {
                                    HapticEngine.shared.tick()
                                    selectedPeriodID = config.id
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color.paletteColor(for: config))
                                            .frame(width: 10, height: 10)
                                        Text(config.displayName)
                                            .font(.lsBody)
                                            .foregroundStyle(Color.lsPrimary)
                                        Spacer()
                                        if selectedPeriodID == config.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.lsBlue)
                                        }
                                    }
                                    .padding(.horizontal, LS.md)
                                    .padding(.vertical, LS.sm)
                                }
                                .buttonStyle(.plain)

                                if config.id != settings.periodConfigs.filter({ $0.isEnabled }).last?.id {
                                    Divider()
                                        .background(Color.lsTertiary.opacity(0.3))
                                        .padding(.leading, LS.md)
                                }
                            }
                        }
                        .lsCard()
                    }

                    // MARK: Due date (optional)
                    VStack(alignment: .leading, spacing: LS.sm) {
                        sectionLabel("Due Date (Optional)")
                        HStack {
                            Button {
                                HapticEngine.shared.tap()
                                withAnimation(.lsSnappy) { showDatePicker.toggle() }
                            } label: {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(Color.lsBlue)
                                    Text(dueDate.map { formatDate($0) } ?? "No due date")
                                        .font(.lsBody)
                                        .foregroundStyle(dueDate == nil ? Color.lsSecondary : Color.lsPrimary)
                                    Spacer()
                                    if dueDate != nil {
                                        Button {
                                            dueDate = nil
                                            showDatePicker = false
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Color.lsTertiary)
                                        }
                                    }
                                }
                                .padding(LS.md)
                            }
                            .buttonStyle(.plain)
                        }
                        .lsCard()

                        if showDatePicker {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { dueDate ?? Date() },
                                    set: { dueDate = $0 }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .tint(Color.lsBlue)
                            .lsCard()
                        }
                    }

                    // MARK: Error
                    if let error {
                        Text(error)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsDestructive)
                            .padding(.horizontal, LS.md)
                    }

                    // MARK: Save button
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to Reminders")
                            }
                        }
                        .font(.lsHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LS.md)
                        .background {
                            RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous)
                                .fill(title.trimmingCharacters(in: .whitespaces).isEmpty
                                      ? Color.lsBlue.opacity(0.4)
                                      : Color.lsBlue)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                    Color.clear.frame(height: LS.xl)
                }
                .padding(.horizontal, LS.md)
                .padding(.top, LS.md)
            }
        }
        .background(Color.lsSurface)
        .onAppear {
            // Wire current period from ScheduleEngine
            let state = store.todayState()
            if let current = state.currentSlot,
               let num = extractPeriodNumber(from: current.period.name) {
                selectedPeriodID = num
            }
            // Open keyboard immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
            // Request reminders access if needed
            Task {
                if !reminders.isAuthorized {
                    _ = await reminders.requestAccess()
                }
            }
        }
    }

    // MARK: - Save

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        error = nil

        let className = settings.config(for: selectedPeriodID)?.displayName ?? "Homework"

        do {
            try await reminders.addAssignment(title: trimmed, className: className, dueDate: dueDate)
            HapticEngine.shared.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.lsLabel)
            .foregroundStyle(Color.lsSecondary)
            .tracking(1)
            .padding(.leading, LS.xs)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func extractPeriodNumber(from name: String) -> Int? {
        let parts = name.split(separator: " ")
        if parts.count == 2, parts[0].lowercased() == "period", let n = Int(parts[1]) {
            return n
        }
        return nil
    }
}

#Preview {
    HomeworkSheet()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
