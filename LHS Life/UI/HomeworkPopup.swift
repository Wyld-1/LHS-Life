//
//  HomeworkPopup.swift
//  LHS Life
//
//  Centered popup card floating over the current tab.
//  Fixed vertical position — ignores keyboard movements entirely.
//

import SwiftUI

struct HomeworkPopup: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @StateObject private var reminders = RemindersService()

    let onDismiss: () -> Void

    @State private var title             = ""
    @State private var selectedPeriodID: Int? = 1
    @State private var dueDate: Date?    = nil
    @State private var priority          = ReminderPriority.none
    @State private var showInlinePicker  = false
    @State private var isSaving          = false
    @State private var errorMessage: String? = nil
    @FocusState private var titleFocused: Bool

    private var enabledPeriods: [PeriodConfig] {
        settings.periodConfigs.filter { $0.isEnabled }
    }

    private var selectedConfig: PeriodConfig? {
        guard let id = selectedPeriodID else { return nil }
        return settings.config(for: id)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    titleFocused = false
                    withAnimation(.lsSnappy) { onDismiss() }
                }

            card
                .frame(maxWidth: 400)
                .padding(.horizontal, LS.xl)
                .offset(y: -40)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            selectedPeriodID = defaultPeriodID()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
            Task { if !reminders.isAuthorized { _ = await reminders.requestAccess() } }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: LS.sm) {

            // Assignment title
            TextField("Assignment name", text: $title)
                .font(.lsBody)
                .foregroundStyle(Color.lsPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit {
                    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await save() }
                }
                .padding(.horizontal, LS.md)
                .padding(.vertical, LS.sm + 2)
                .background(Color.lsSurfaceRaised)
                .clipShape(Capsule())

            // Class | Priority | Date row
            HStack(spacing: LS.sm) {
                classMenu
                priorityButton
                dateMenu
            }

            // Inline date picker
            if showInlinePicker {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() },
                        set: { dueDate = $0; HapticEngine.shared.tick() }
                    ),
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Color.lsBlue)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onChange(of: dueDate) { _, _ in
                    withAnimation(.lsSnappy) { showInlinePicker = false }
                }
            }

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.lsCaption)
                    .foregroundStyle(Color.lsDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Cancel / Save
            HStack(spacing: LS.sm) {
                Button("Cancel") {
                    titleFocused = false
                    withAnimation(.lsSnappy) { onDismiss() }
                }
                .font(.lsHeadline)
                .foregroundStyle(Color.lsPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LS.sm + 2)
                .background(Color.lsSurfaceRaised)
                .clipShape(Capsule())
                .buttonStyle(.plain)

                Button { Task { await save() } } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text("Save").font(.lsHeadline).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LS.sm + 2)
                    .background(
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.lsBlue.opacity(0.4) : Color.lsBlue
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding(.top, LS.xs)
        }
        .padding(LS.md)
        .background {
            RoundedRectangle(cornerRadius: LS.radiusXl, style: .continuous)
                .fill(Color.lsSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: LS.radiusXl, style: .continuous)
                        .strokeBorder(
                            Color.lsPrimary.opacity(LS.hairlineOpacity),
                            lineWidth: LS.hairlineWidth
                        )
                }
        }
        .shadow(color: .black.opacity(0.35), radius: 40, y: 8)
        .animation(.lsSnappy, value: showInlinePicker)
    }

    // MARK: - Class Menu

    private var classMenu: some View {
        Menu {
            Picker("Class", selection: $selectedPeriodID) {
                ForEach(enabledPeriods) { config in
                    Text(config.displayName).tag(Optional(config.id))
                }
            }
            Divider()
            Picker("Class", selection: $selectedPeriodID) {
                Text("None").tag(Optional<Int>.none)
            }
        } label: {
            HStack(spacing: LS.sm) {
                if let config = selectedConfig {
                    Circle()
                        .fill(Color.paletteColor(for: config))
                        .frame(width: 10, height: 10)
                        .lsSphereRim()
                } else {
                    Circle()
                        .fill(Color.lsSurfaceRaised)
                        .frame(width: 10, height: 10)
                }
                Text(selectedConfig?.displayName ?? "None")
                    .font(.lsCaption)
                    .foregroundStyle(Color.lsSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.lsSecondary)
            }
            .padding(.horizontal, LS.sm)
            .frame(height: LS.chipHeight)
            .frame(maxWidth: .infinity)
            .background(Color.lsSurfaceRaised)
            .clipShape(Capsule())
        }
        .tint(Color.lsPrimary)
        .onChange(of: selectedPeriodID) { _, _ in HapticEngine.shared.tick() }
    }

    // MARK: - Priority Button
    // Fixed-width. Always shows !!! — unlit ones are gray, lit ones orange.
    // Cycles: none → low(!) → medium(!!) → high(!!!) → none. No menu.

    private var priorityButton: some View {
        Button {
            priority = priority.next
            HapticEngine.shared.tick()
        } label: {
            HStack(spacing: 1) {
                Text("!")
                    .foregroundStyle(priority == .low || priority == .medium || priority == .high
                                     ? Color.lsOrange : Color.lsTertiary)
                Text("!")
                    .foregroundStyle(priority == .medium || priority == .high
                                     ? Color.lsOrange : Color.lsTertiary)
                Text("!")
                    .foregroundStyle(priority == .high
                                     ? Color.lsOrange : Color.lsTertiary)
            }
            .font(.system(size: 14, weight: .black, design: .rounded))
            .padding(.horizontal, LS.sm)
            .frame(height: LS.chipHeight)
            .fixedSize()
            .background(priority == .none ? Color.lsSurfaceRaised : Color.lsBlue.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Menu helpers

    private func tomorrowDayNumber() -> Int {
        Calendar.current.component(.day, from: nextDay())
    }
    private func nextMondayDayNumber() -> Int {
        Calendar.current.component(.day, from: nextMonday())
    }

    // MARK: - Date Menu

    private var dateMenu: some View {
        Menu {
            Button {
                dueDate = nextDay()
                showInlinePicker = false
                HapticEngine.shared.tick()
            } label: {
                Label("Tomorrow", systemImage: "\(tomorrowDayNumber()).calendar")
            }
            Button {
                dueDate = nextMonday()
                showInlinePicker = false
                HapticEngine.shared.tick()
            } label: {
                Label("Next Monday", systemImage: "\(nextMondayDayNumber()).calendar")
            }
            Button {
                titleFocused = false
                withAnimation(.lsSnappy) { showInlinePicker.toggle() }
            } label: {
                Label("Custom", systemImage: "ellipsis")
            }
            if dueDate != nil {
                Divider()
                Button("Remove Date", role: .destructive) {
                    dueDate = nil
                    showInlinePicker = false
                    HapticEngine.shared.tick()
                }
            }
        } label: {
            HStack(spacing: LS.xs) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(dueDate == nil ? Color.lsSecondary : Color.lsBlue)
                Text(dueDate.map { shortDate($0) } ?? "Due")
                    .font(.lsCaption)
                    .foregroundStyle(dueDate == nil ? Color.lsSecondary : Color.lsBlue)
                    .lineLimit(1)
            }
            .padding(.horizontal, LS.sm)
            .frame(height: LS.chipHeight)
            .fixedSize()
            .background(dueDate == nil ? Color.lsSurfaceRaised : Color.lsBlue.opacity(0.12))
            .clipShape(Capsule())
        }
        .simultaneousGesture(TapGesture().onEnded { titleFocused = false })
    }

    // MARK: - Save

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        // Pass nil when no class is selected — no notes written on the reminder.
        let className = selectedConfig?.displayName
        do {
            try await reminders.addAssignment(
                title: trimmed,
                className: className,
                dueDate: dueDate,
                priority: priority.rawValue
            )
            HapticEngine.shared.success()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    // MARK: - Default Period

    /// Which class the popup pre-selects when it opens.
    ///
    /// The rule is "the class this assignment is most likely FOR", which is
    /// not the same as "the next thing on the schedule":
    ///
    ///   In a numbered period   → that period
    ///   Passing time           → the slot that just ended, if it was a class
    ///                            (you walk out and add the homework right
    ///                            then)
    ///   Lunch or Break         → None
    ///   Passing time after     → None — the slot that just ended was Lunch,
    ///   lunch                    and nothing is inferred past it
    ///   Anything else          → None
    ///
    /// "Anything else" covers before school, after school, weekends, summer,
    /// holidays and Pathways days. Those all previously fell through to
    /// `enabledPeriods.first?.id`, which is why the popup opened on Period 1
    /// essentially any time school wasn't actively running.
    ///
    /// Nothing here reaches BACKWARD past a non-class slot. Once you're on
    /// the far side of lunch the last class is far enough behind you that
    /// guessing it is worse than guessing nothing.
    private func defaultPeriodID() -> Int? {
        let state = store.todayState()

        switch state.dayState {
        case .inSession:
            // Lunch and Break are "in session" but aren't classes, so their
            // period-number parse yields nil and this lands on None.
            return enabledPeriodID(
                state.currentSlot.flatMap { ScheduleEngine.periodNumber(from: $0.period.name) }
            )

        case .betweenPeriods:
            return previousSlotPeriodID()

        case .beforeSchool, .afterSchool, .noSchedule, .pathwaysDay, .holiday:
            return nil
        }
    }

    /// The slot immediately behind us, if it was a numbered class. Lunch and
    /// Break parse to nil here, so the passing time after lunch is None.
    private func previousSlotPeriodID() -> Int? {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let slot = ScheduleEngine.previousSlot(
            schedule: store.bellSchedule(for: dayKey),
            settings: settings
        )
        return enabledPeriodID(slot.flatMap { ScheduleEngine.periodNumber(from: $0.period.name) })
    }

    /// Only pre-select a period the student actually has configured and
    /// enabled — otherwise fall back to None rather than selecting a class
    /// they've turned off.
    private func enabledPeriodID(_ num: Int?) -> Int? {
        guard let num, settings.config(for: num)?.isEnabled == true else { return nil }
        return num
    }

    // MARK: - Helpers

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

#Preview {
    HomeworkPopup(onDismiss: {})
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
