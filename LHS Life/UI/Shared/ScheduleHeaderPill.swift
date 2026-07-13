//
//  ScheduleHeaderPill.swift
//  LHS Life
//
//  The schedule status pill — "3 min left in Period 2", "No school today",
//  etc. Shared by iPhone (PhoneHeaderRow) and iPad (sidebar Today module).
//  Platform-agnostic: no device-specific layout here, just the pill itself.
//

import SwiftUI

// MARK: - Glass modifier

private struct CapsuleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
        }
    }
}

// MARK: - Schedule Header Pill

struct ScheduleHeaderPill: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    var onPillTap: (() -> Void)? = nil
    var onEventTap: ((SchoolEvent) -> Void)? = nil
    /// When true, suppresses the pill's own glassEffect — use when the system
    /// (e.g. tabViewBottomAccessory) already provides the glass surface.
    var suppressGlass: Bool = false

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var apExamState: APExamService.APExamState {
        let dayKey = DateFormatter.isoDay.string(from: now)
        return APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
    }

    private var inAPMode: Bool {
        guard settings.apModeEnabledToday else { return false }
        if case .mine(_, let start, let end, _) = apExamState {
            return now >= start && now < end
        }
        return false
    }

    private var apModeExamDone: Bool {
        guard settings.apModeEnabledToday else { return false }
        if case .mine(_, _, let end, _) = apExamState { return now >= end }
        return false
    }

    private var state: ScheduleEngine.ScheduleState { store.todayState(at: now) }

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
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .frame(minHeight: 44)
        .overlay(alignment: .leading) {
            if !settings.apModeEnabledToday {
                if state.dayState == .inSession, let slot = state.currentSlot {
                    GeometryReader { geo in
                        Capsule()
                            .fill(progressColor(slot: slot))
                            .opacity(0.18)
                            .frame(width: geo.size.width * slot.progress)
                            .animation(.lsFade, value: slot.progress)
                    }
                } else if state.dayState == .betweenPeriods, let next = state.nextSlot {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.lsTertiary)
                            .opacity(0.18)
                            .frame(width: geo.size.width * passingProgress(nextStart: next.startDate))
                    }
                }
            }
        }
        .clipShape(Capsule())
        .background {
            if #available(iOS 26, *) { Color.clear } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            if let event = tappableEvent, let onEventTap {
                onEventTap(event)
            } else if onPillTap != nil {
                onPillTap?()
            }
        }
        .ifTrue(!suppressGlass) { $0.modifier(CapsuleGlassModifier()) }
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: Text

    private var todayScheduleType: ScheduleType? {
        store.bellSchedules[DateFormatter.isoDay.string(from: now)]?.scheduleType
    }

    private func scheduleLabel(suppressRegular: Bool = true) -> String? {
        guard let type = todayScheduleType else { return nil }
        if suppressRegular && type == .regular { return nil }
        return type.scheduleLabel
    }

    private func scheduleLabelFor(dayKey: String) -> String? {
        guard let type = store.bellSchedules[dayKey]?.scheduleType else { return nil }
        return type.scheduleLabel
    }

    private var primaryText: String {
        if inAPMode, case .mine(let name, _, _, _) = apExamState { return name }
        if apModeExamDone { return afterSchoolPrimary }
        switch state.dayState {
        case .inSession:
            guard let slot = state.currentSlot else { return "" }
            return "\(Int(ceil(slot.timeRemaining / 60))) min left in \(slot.displayName)"
        case .betweenPeriods:
            guard let next = state.nextSlot else { return "" }
            return "\(next.displayName) in \(Int(ceil(next.startDate.timeIntervalSince(now) / 60))) min"
        case .beforeSchool:
            guard let next = state.nextSlot else { return "No school today" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            return mins > 30 ? "School at \(ScheduleEngine.timeString(next.startDate))" : "School in \(mins) min"
        case .afterSchool:   return afterSchoolPrimary
        case .holiday:       return "No school today"
        case .pathwaysDay:   return "Internship Day"
        case .noSchedule:
            let wd = Calendar.current.component(.weekday, from: now)
            return (wd >= 2 && wd <= 6) ? "No school today" : weekendPrimary
        }
    }

    private var afterSchoolPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:    return "Happy Friday! 🎉"
        case 7, 1: return "Enjoy the weekend!"
        default:   return "School's out"
        }
    }

    private var weekendPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:    return "Happy Friday! 🎉"
        case 7, 1: return "Enjoy the weekend!"
        default:   return "No school today"
        }
    }

    private var secondaryText: String? {
        if inAPMode, case .mine(_, _, let end, _) = apExamState {
            return "Until \(ScheduleEngine.timeString(end))"
        }
        if apModeExamDone { return tomorrowSecondary }
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
            // Show schedule type if available; otherwise show nothing (no next-event preview).
            // We never want tomorrow's event appearing before today's school has started.
            if let label = scheduleLabel(suppressRegular: false) { return label }
            return nil
        case .holiday:
            return store.events(on: DateFormatter.isoDay.string(from: now))
                .first { $0.category == .holiday }.map { $0.title }
        case .afterSchool, .noSchedule:
            switch weekday {
            case 6:  return saturdaySecondary
            case 7:  return saturdayOrSundaySecondary
            case 1:  return sundaySecondary
            default: return tomorrowSecondary
            }
        case .pathwaysDay: return nil
        }
    }

    private var saturdaySecondary: String? {
        let cal = Calendar.current
        guard let sat = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sat))
            .first { $0.category != .bellSchedule }.map { upcomingEventText($0) }
    }

    private var saturdayOrSundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        guard let sun = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sun))
            .first { $0.category != .bellSchedule }.map { upcomingEventText($0) }
    }

    private var sundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        guard let mon = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let monKey = DateFormatter.isoDay.string(from: mon)
        return store.events(on: monKey).first { $0.category != .bellSchedule }.map { upcomingEventText($0) }
            ?? scheduleLabelFor(dayKey: monKey).map { "Tomorrow: \($0)" }
    }

    private var tomorrowSecondary: String? {
        let cal = Calendar.current
        guard let tom = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: tom))
            .first { $0.category != .bellSchedule }.map { upcomingEventText($0) }
    }

    private var tappableEvent: SchoolEvent? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        switch state.dayState {
        case .afterSchool, .noSchedule:
            switch weekday {
            case 6:  return eventOn(daysAhead: 1)
            case 7:  return saturdayOrSundayEvent
            case 1:  return sundayEvent
            default: return eventOn(daysAhead: 1)
            }
        case .holiday:
            return store.events(on: DateFormatter.isoDay.string(from: now))
                .first { $0.category == .holiday }
        default: return nil
        }
    }

    private func eventOn(daysAhead: Int) -> SchoolEvent? {
        let cal = Calendar.current
        guard let d = cal.date(byAdding: .day, value: daysAhead, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: d)).first { $0.category != .bellSchedule }
    }

    private var saturdayOrSundayEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) { return event }
        guard let sun = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sun)).first { $0.category != .bellSchedule }
    }

    private var sundayEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) { return event }
        guard let mon = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: mon)).first { $0.category != .bellSchedule }
    }

    private func upcomingEventText(_ event: SchoolEvent) -> String {
        let cal = Calendar.current
        let label = cal.isDateInTomorrow(event.startDate) ? "Tomorrow"
                  : cal.isDateInToday(event.startDate)   ? "Today"
                  : DateFormatter.shortWeekday.string(from: event.startDate)
        return event.isAllDay
            ? "\(label): \(event.title)"
            : "\(label): \(event.title) at \(ScheduleEngine.timeString(event.startDate))"
    }

    private func progressColor(slot: ScheduleEngine.ActiveSlot) -> Color {
        guard let config = slot.config else { return Color.lsTertiary }
        return Color.paletteColor(for: config)
    }

    private func passingProgress(nextStart: Date) -> Double {
        let dayKey = DateFormatter.isoDay.string(from: now)
        guard let schedule = store.bellSchedules[dayKey],
              let prevEnd = schedule.periods.compactMap({ p -> Date? in
                  guard let e = p.endDate(on: schedule.date), e <= now else { return nil }
                  return e
              }).max()
        else { return 0 }
        let total = nextStart.timeIntervalSince(prevEnd)
        guard total > 0 else { return 0 }
        return max(0, min(1, now.timeIntervalSince(prevEnd) / total))
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.now = Date()
                LiveActivityService.shared.endIfSchoolOver(state: self.store.todayState(at: self.now))
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
}

private extension DateFormatter {
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

#Preview {
    ZStack(alignment: .top) {
        Color.lsBackground.ignoresSafeArea()
        ScheduleHeaderPill()
            .environment(CalendarStore())
            .environment(UserSettings.shared)
            .padding(.horizontal, LS.md)
            .padding(.top, LS.sm)
    }
}
