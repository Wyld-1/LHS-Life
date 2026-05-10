//
//  ScheduleHeader.swift
//  LHS Life
//
//  Two independent components:
//
//  ScheduleHeaderPill — the pill with text and progress fill. No settings button.
//                       Used by both iPhone (top) and iPad (bottom accessory).
//
//  SettingsButton     — standalone settings button, always pinned top-right.
//
//  The 1-second timer lives in ScheduleHeaderPill since it owns the live state.
//

import SwiftUI

// MARK: - Settings Button (always top-right, platform-agnostic)

struct SettingsButton: View {
    @Binding var showSettings: Bool

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(Color.lsBlue)
                .font(.system(size: 42, weight: .semibold))
                .shadow(color: .black.opacity(0.5), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Header Pill

struct ScheduleHeaderPill: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    /// Called when the pill is tapped — used to navigate to Events tab on iPhone.
    var onPillTap: (() -> Void)? = nil

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var state: ScheduleEngine.ScheduleState {
        store.todayState(at: now)
    }

    // MARK: - Body

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text(primaryText)
                    .font(.lsHeadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let sub = secondaryText {
                    Text(sub)
                        .font(.lsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .overlay(alignment: .leading) {
            // Progress fill — lives inside the glass so clipShape contains it
            if state.dayState == .inSession, let slot = state.currentSlot {
                GeometryReader { geo in
                    Capsule()
                        .fill(progressColor(slot: slot))
                        .opacity(0.18)
                        .frame(width: geo.size.width * slot.progress)
                        .animation(.lsFade, value: slot.progress)
                }
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                Capsule().glassEffect(.regular.interactive())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            guard onPillTap != nil else { return }
            HapticEngine.shared.tap()
            onPillTap?()
        }
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Text Logic

    /// The schedule type for today — used in secondary text.
    private var todayScheduleType: ScheduleType? {
        let dayKey = DateFormatter.isoDay.string(from: now)
        return store.bellSchedules[dayKey]?.scheduleType
    }

    /// Human-readable schedule type label, suppressing nil for .regular
    /// since "Regular Schedule" is only worth showing on Sunday preview.
    private func scheduleLabel(suppressRegular: Bool = true) -> String? {
        guard let type = todayScheduleType else { return nil }
        if suppressRegular && type == .regular { return nil }
        return type.rawValue + " Schedule"
    }

    /// Schedule label for a future day (Sunday showing Monday).
    private func scheduleLabelFor(dayKey: String) -> String? {
        guard let type = store.bellSchedules[dayKey]?.scheduleType else { return nil }
        return type.rawValue + " Schedule"
    }

    private var primaryText: String {
        switch state.dayState {
        case .inSession:
            guard let slot = state.currentSlot else { return "" }
            let mins = Int(ceil(slot.timeRemaining / 60))
            return "\(mins) min left in \(slot.displayName)"

        case .betweenPeriods:
            guard let next = state.nextSlot else { return "" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            return "\(next.displayName) in \(mins) min"

        case .beforeSchool:
            guard let next = state.nextSlot else { return "No school today" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            return mins > 30
                ? "School at \(ScheduleEngine.timeString(next.startDate))"
                : "School in \(mins) min"

        case .afterSchool:
            return afterSchoolPrimary

        case .holiday:
            return "No school today"

        case .pathwaysDay:
            return "Internship Day"

        case .noSchedule:
            // App blocks UI until data loads, so noSchedule on a weekday
            // means the calendar genuinely has no event for today = no school.
            // On weekends it's expected.
            let weekday = Calendar.current.component(.weekday, from: now)
            return (weekday >= 2 && weekday <= 6) ? "No school today" : weekendPrimary
        }
    }

    private var afterSchoolPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:  return "Happy Friday! 🎉"
        case 7:  return "Enjoy the weekend!"
        case 1:  return "Enjoy the weekend!"
        default: return "School's out"
        }
    }

    private var weekendPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:  return "Happy Friday! 🎉"
        case 7, 1: return "Enjoy the weekend!"
        default: return "No school today"
        }
    }

    private var secondaryText: String? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)

        switch state.dayState {
        case .inSession:
            guard let next = state.nextSlot else { return nil }
            return "Next: \(next.displayName) at \(ScheduleEngine.timeString(next.startDate))"

        case .betweenPeriods:
            guard let next = state.nextSlot else { return nil }
            return "Until \(ScheduleEngine.timeString(next.endDate))"

        case .beforeSchool:
            // Always show schedule type — most useful info before school
            return scheduleLabel(suppressRegular: false)
                .map { $0 } ?? nil

        case .holiday:
            // Show the holiday event name
            let dayKey = DateFormatter.isoDay.string(from: now)
            return store.events(on: dayKey)
                .first { $0.category == .holiday }
                .map { $0.title }

        case .afterSchool, .noSchedule:
            switch weekday {
            case 6:  // Friday — show Saturday events
                return saturdaySecondary
            case 7:  // Saturday — show Saturday remaining or Sunday events
                return saturdayOrSundaySecondary
            case 1:  // Sunday — show Sunday events, then Monday schedule
                return sundaySecondary
            default: // Weekday after school — show tomorrow's event
                return tomorrowSecondary
            }

        case .pathwaysDay:
            return nil
        }
    }

    // MARK: - Secondary text helpers

    /// Friday: show a Saturday non-bell event if any, else nil.
    private var saturdaySecondary: String? {
        let cal = Calendar.current
        guard let saturday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let satKey = DateFormatter.isoDay.string(from: saturday)
        return store.events(on: satKey)
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    /// Saturday: show remaining Saturday events, then Sunday events.
    private var saturdayOrSundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        guard let sunday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let sunKey = DateFormatter.isoDay.string(from: sunday)
        return store.events(on: sunKey)
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    /// Sunday: show Sunday events, then Monday's schedule type or event.
    private var sundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        // Sunday events first
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        // Monday event
        guard let monday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let monKey = DateFormatter.isoDay.string(from: monday)
        if let event = store.events(on: monKey).first(where: { $0.category != .bellSchedule }) {
            return upcomingEventText(event)
        }
        // Fall back to Monday's schedule type — always show, even Regular
        return scheduleLabelFor(dayKey: monKey).map { "Tomorrow: \($0)" }
    }

    /// Weekday after school: show tomorrow's notable event.
    private var tomorrowSecondary: String? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let tomorrowKey = DateFormatter.isoDay.string(from: tomorrow)
        return store.events(on: tomorrowKey)
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    private func upcomingEventText(_ event: SchoolEvent) -> String {
        let cal = Calendar.current
        let isTomorrow = cal.isDateInTomorrow(event.startDate)
        let isToday = cal.isDateInToday(event.startDate)
        let dayLabel: String
        if isTomorrow      { dayLabel = "Tomorrow" }
        else if isToday    { dayLabel = "Today" }
        else               { dayLabel = DateFormatter.shortWeekday.string(from: event.startDate) }
        return event.isAllDay
            ? "\(dayLabel): \(event.title)"
            : "\(dayLabel): \(event.title) at \(ScheduleEngine.timeString(event.startDate))"
    }

    private func progressColor(slot: ScheduleEngine.ActiveSlot) -> Color {
        guard let config = slot.config else { return Color.lsBlue }
        return Color.paletteColor(for: config)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                self.now = Date()
                LiveActivityService.shared.update(
                    state: self.store.todayState(at: self.now),
                    settings: self.settings
                )
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
}

// MARK: - Convenience: iPhone header (pill + settings button together)
// Used only on iPhone where they appear as one unit at the top.

struct ScheduleHeader: View {
    @Binding var showSettings: Bool
    var onPillTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: LS.sm) {
            ScheduleHeaderPill(onPillTap: onPillTap)
                .frame(maxWidth: .infinity)
            SettingsButton(showSettings: $showSettings)
        }
    }
}

private extension DateFormatter {
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}

#Preview {
    ZStack(alignment: .top) {
        Color.lsBackground.ignoresSafeArea()
        ScheduleHeader(showSettings: .constant(false))
            .environment(CalendarStore())
            .environment(UserSettings.shared)
            .padding(.horizontal, LS.md)
            .padding(.top, LS.sm)
    }
}
