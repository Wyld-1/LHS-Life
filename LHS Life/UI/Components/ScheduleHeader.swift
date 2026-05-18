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
//  Glass notes (iOS 26):
//  — .glassEffect(_, in: Shape) must be the LAST modifier on a view.
//    It replaces the background entirely. Never nest it inside .background{}.
//  — GlassEffectContainer coordinates blending between sibling glass views.
//    Wrap the HStack containing pill + button so they share one glass surface.
//  — Each child still declares its own .glassEffect with its own shape.
//

import SwiftUI

// MARK: - Settings Button

struct SettingsButton: View {
    @Binding var showSettings: Bool
    var showBadge: Bool = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image("lhs-lightning")
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 28, height: 28)
                    .padding(12)
                    // iOS 17–25 fallback — glass applied via background
                    .background {
                        if #available(iOS 26, *) {
                            Color.clear
                        } else {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay { Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5) }
                                .shadow(color: .black.opacity(0.3), radius: 8)
                        }
                    }
                    // iOS 26: glass as outermost modifier on the whole button content
                    .modifier(CircleGlassModifier())

                if showBadge {
                    Circle()
                        .fill(Color.lsDestructive)
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass modifier helpers
// Avoids #available inside result builders (causes layout issues).

private struct CircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
        }
    }
}

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

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var apExamState: APExamService.APExamState {
        let dayKey = DateFormatter.isoDay.string(from: now)
        return APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
    }

    /// True if user is in AP Mode and exam has started but not ended.
    private var inAPMode: Bool {
        guard settings.apModeEnabledToday else { return false }
        if case .mine(_, let start, let end, _) = apExamState {
            return now >= start && now < end
        }
        return false
    }

    /// True if user is in AP Mode and exam has ended — treat as afterSchool.
    private var apModeExamDone: Bool {
        guard settings.apModeEnabledToday else { return false }
        if case .mine(_, _, let end, _) = apExamState {
            return now >= end
        }
        return false
    }

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
        // iOS 17–25 fallback background
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
                HapticEngine.shared.tap()
                onEventTap(event)
            } else if onPillTap != nil {
                HapticEngine.shared.tap()
                onPillTap?()
            }
        }
        .modifier(CapsuleGlassModifier())
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Text Logic

    private var todayScheduleType: ScheduleType? {
        let dayKey = DateFormatter.isoDay.string(from: now)
        return store.bellSchedules[dayKey]?.scheduleType
    }

    private func scheduleLabel(suppressRegular: Bool = true) -> String? {
        guard let type = todayScheduleType else { return nil }
        if suppressRegular && type == .regular { return nil }
        return type.rawValue + " Schedule"
    }

    private func scheduleLabelFor(dayKey: String) -> String? {
        guard let type = store.bellSchedules[dayKey]?.scheduleType else { return nil }
        return type.rawValue + " Schedule"
    }

    private var primaryText: String {
        // AP Mode overrides everything
        if inAPMode {
            if case .mine(let name, _, _, _) = apExamState {
                return name
            }
        }
        if apModeExamDone { return afterSchoolPrimary }

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
        case .afterSchool:   return afterSchoolPrimary
        case .holiday:       return "No school today"
        case .pathwaysDay:   return "Internship Day"
        case .noSchedule:
            let weekday = Calendar.current.component(.weekday, from: now)
            return (weekday >= 2 && weekday <= 6) ? "No school today" : weekendPrimary
        }
    }

    private var afterSchoolPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:     return "Happy Friday! 🎉"
        case 7, 1:  return "Enjoy the weekend!"
        default:    return "School's out"
        }
    }

    private var weekendPrimary: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:     return "Happy Friday! 🎉"
        case 7, 1:  return "Enjoy the weekend!"
        default:    return "No school today"
        }
    }

    private var secondaryText: String? {
        // AP Mode overrides
        if inAPMode {
            if case .mine(_, _, let end, _) = apExamState {
                return "Until \(ScheduleEngine.timeString(end))"
            }
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
            return scheduleLabel(suppressRegular: false).map { $0 } ?? nil
        case .holiday:
            let dayKey = DateFormatter.isoDay.string(from: now)
            return store.events(on: dayKey).first { $0.category == .holiday }.map { $0.title }
        case .afterSchool, .noSchedule:
            switch weekday {
            case 6:  return saturdaySecondary
            case 7:  return saturdayOrSundaySecondary
            case 1:  return sundaySecondary
            default: return tomorrowSecondary
            }
        case .pathwaysDay:
            return nil
        }
    }

    private var saturdaySecondary: String? {
        let cal = Calendar.current
        guard let saturday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: saturday))
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    private var saturdayOrSundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        guard let sunday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sunday))
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    private var sundaySecondary: String? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) {
            return upcomingEventText(event)
        }
        guard let monday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let monKey = DateFormatter.isoDay.string(from: monday)
        if let event = store.events(on: monKey).first(where: { $0.category != .bellSchedule }) {
            return upcomingEventText(event)
        }
        return scheduleLabelFor(dayKey: monKey).map { "Tomorrow: \($0)" }
    }

    private var tomorrowSecondary: String? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: tomorrow))
            .first { $0.category != .bellSchedule }
            .map { upcomingEventText($0) }
    }

    /// The SchoolEvent referenced in the secondary text, if any.
    /// Used to route pill taps directly to that event in the calendar.
    private var tappableEvent: SchoolEvent? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        switch state.dayState {
        case .afterSchool, .noSchedule:
            switch weekday {
            case 6:  return saturdayEvent
            case 7:  return saturdayOrSundayEvent
            case 1:  return sundayEvent
            default: return tomorrowEvent
            }
        case .holiday:
            let dayKey = DateFormatter.isoDay.string(from: now)
            return store.events(on: dayKey).first { $0.category == .holiday }
        default: return nil
        }
    }

    private var tomorrowEvent: SchoolEvent? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: tomorrow))
            .first { $0.category != .bellSchedule }
    }
    private var saturdayEvent: SchoolEvent? {
        let cal = Calendar.current
        guard let saturday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: saturday))
            .first { $0.category != .bellSchedule }
    }
    private var saturdayOrSundayEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) { return event }
        guard let sunday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sunday)).first { $0.category != .bellSchedule }
    }
    private var sundayEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .bellSchedule && $0.startDate > now }) { return event }
        guard let monday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: monday)).first { $0.category != .bellSchedule }
    }

    private func upcomingEventText(_ event: SchoolEvent) -> String {
        let cal = Calendar.current
        let dayLabel: String
        if cal.isDateInTomorrow(event.startDate)  { dayLabel = "Tomorrow" }
        else if cal.isDateInToday(event.startDate) { dayLabel = "Today" }
        else { dayLabel = DateFormatter.shortWeekday.string(from: event.startDate) }
        return event.isAllDay
            ? "\(dayLabel): \(event.title)"
            : "\(dayLabel): \(event.title) at \(ScheduleEngine.timeString(event.startDate))"
    }

    private func progressColor(slot: ScheduleEngine.ActiveSlot) -> Color {
        guard let config = slot.config else { return Color.lsTertiary }
        return Color.paletteColor(for: config)
    }

    /// Progress 0→1 through passing time, computed from the previous slot's end to next slot's start.
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

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                self.now = Date()
                let state = self.store.todayState(at: self.now)
                LiveActivityService.shared.endIfSchoolOver(state: state)
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
}

// MARK: - Schedule Header (iPhone: pill + settings button)

struct ScheduleHeader: View {
    @Binding var showSettings: Bool
    var onPillTap: (() -> Void)? = nil
    var onEventTap: ((SchoolEvent) -> Void)? = nil

    @Environment(UserSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    private var showBadge: Bool {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let state = APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
        if case .none = state { return false }
        return !settings.apBadgeCleared
    }

    private var apAccentColor: Color {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let state = APExamService.examState(
            for: dayKey, events: store.events(on: dayKey), settings: settings
        )
        if case .mine(_, _, _, let config) = state, let config = config {
            return Color.paletteColor(for: config)
        }
        return Color.lsBlue
    }

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                // GlassEffectContainer lets pill + button share one continuous glass surface.
                // Each child applies .glassEffect with its own shape via ViewModifier above.
                GlassEffectContainer(spacing: LS.sm) {
                    HStack(spacing: LS.sm) {
                        ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                            .frame(maxWidth: .infinity)
                        SettingsButton(showSettings: $showSettings, showBadge: showBadge)
                    }
                }
            } else {
                HStack(spacing: LS.sm) {
                    ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                        .frame(maxWidth: .infinity)
                    SettingsButton(showSettings: $showSettings, showBadge: showBadge)
                }
            }
        }
        .onChange(of: showSettings) { _, showing in
            if showing { settings.apBadgeCleared = true }
        }
    }
}

// MARK: - AP Exam Banner

struct APExamBanner: View {
    let examName: String
    let isSilenced: Bool
    let accentColor: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LS.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(examName)
                    .font(.lsHeadline)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(isSilenced ? "AP Mode on" : "AP Mode off")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.lsSecondary)
            }
            Spacer()
            Button(action: onToggle) {
                Text(isSilenced ? "Exit AP Mode" : "AP Mode")
                    .font(.lsLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, LS.sm)
                    .padding(.vertical, 5)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .background(accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .animation(.lsSnappy, value: isSilenced)
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
