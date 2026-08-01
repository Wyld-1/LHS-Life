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
    /// When true, suppresses the pill's own background/glass surface — use when
    /// the system already provides one (nav bar toolbar item,
    /// tabViewBottomAccessory). Covers BOTH the iOS 26 glassEffect and the
    /// pre-26 frosted Capsule + shadow; either one double-applies material when
    /// the pill sits inside a surface the system already drew.
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
                Text(DebugClock.shared.forcedPrimaryText ?? primaryText)
                    .font(.lsHeadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let sub = DebugClock.shared.forcedPrimaryText != nil
                    ? DebugClock.shared.forcedSecondaryText
                    : secondaryText {
                    Text(sub)
                        .font(.lsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer()
        }
        .padding(.horizontal, LS.md)
        // Fixed 44 (not minHeight) — a nav bar constrains principal-item height
        // strictly, so the pill must commit to one. 17pt headline + 2 spacing +
        // 12pt caption ≈ 31pt of text, which clears 44 comfortably; the vertical
        // padding that used to push this to ~47 is gone. Subtitle is lineLimit(1)
        // for the same reason — two caption lines would overflow 44.
        .frame(height: 44)
        .overlay(alignment: .leading) {
            if let forced = DebugClock.shared.forcedProgress {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.lsBlue)
                        .opacity(0.18)
                        .frame(width: geo.size.width * forced)
                }
            } else if !settings.apModeEnabledToday {
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
            if #available(iOS 26, *) { Color.clear } else if suppressGlass { Color.clear } else {
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
        .onAppear  { now = DebugClock.shared.now; startTimer() }
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
        if isSummerWindow {
            if let event = todayEvent { return event.title }
            return "Enjoy summer \u{1F3DC}\u{FE0F}"
        }
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
        if isSummerWindow {
            if let event = todayEvent {
                // "Today at {time}" — all-day events have no time to state,
                // so the subtitle is simply omitted for those.
                guard !event.isAllDay else { return nil }
                return "Today at \(ScheduleEngine.timeString(event.startDate))"
            }
            if let event = tomorrowEvent { return upcomingEventText(event) }
            guard let label = orientationDateLabel else { return nil }
            return "Orientation on \(label)"
        }
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
                .first { $0.isHoliday }.map { $0.title }
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

    // MARK: Summer Message
    //
    // Aug 1 through the day before Class Orientation Day, when there's no
    // real event happening today, the header shows "Enjoy summer" instead
    // of the normal generic "No school today"/weekend text. Once
    // Orientation Day itself arrives, normal schedule-based header text
    // resumes on its own (Orientation Day has real synthesized periods by
    // then, so state.dayState is no longer .noSchedule).

    /// Aug 1 of the current calendar year through (exclusive) the real,
    /// dynamic Class Orientation Day date — not hardcoded, reads directly
    /// from the feed the same way ClassOrientationService does.
    private var orientationEvent: SchoolEvent? {
        store.events.first {
            $0.title.trimmingCharacters(in: .whitespaces).lowercased() == "class orientation day"
        }
    }

    private var summerMessageWindow: (start: Date, end: Date)? {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        guard let aug1 = cal.date(from: DateComponents(year: year, month: 8, day: 1)) else { return nil }
        guard let orientation = orientationEvent else { return nil }
        let orientationDay = cal.startOfDay(for: orientation.startDate)
        guard orientationDay > aug1 else { return nil }
        return (aug1, orientationDay)
    }

    private var isSummerWindow: Bool {
        guard let window = summerMessageWindow else { return false }
        let today = Calendar.current.startOfDay(for: now)
        return today >= window.start && today < window.end
    }

    /// FLAG FOR REVIEW: excludes "Summer School" specifically, same reasoning
    /// as before — it's an all-day marker on nearly every July weekday in the
    /// real feed, so treating it as a displayable "real event" would mean the
    /// placeholders almost never show. Applies to both today's and tomorrow's
    /// lookup identically. If Summer School SHOULD count, drop this exclusion
    /// from both.
    private var todayEvent: SchoolEvent? {
        let dayKey = DateFormatter.isoDay.string(from: now)
        return store.events(on: dayKey).first {
            $0.category != .schedules &&
            $0.title.trimmingCharacters(in: .whitespaces).lowercased() != "summer school"
        }
    }

    private var tomorrowEvent: SchoolEvent? {
        let cal = Calendar.current
        guard let tom = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let dayKey = DateFormatter.isoDay.string(from: tom)
        return store.events(on: dayKey).first {
            $0.category != .schedules &&
            $0.title.trimmingCharacters(in: .whitespaces).lowercased() != "summer school"
        }
    }

    private var orientationDateLabel: String? {
        guard let orientation = orientationEvent else { return nil }
        let cal = Calendar.current
        let day = cal.component(.day, from: orientation.startDate)
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        let month = f.string(from: orientation.startDate)
        return "\(month) \(day)\(ordinalSuffix(for: day))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 11, 12, 13: return "th"
        default:
            switch day % 10 {
            case 1:  return "st"
            case 2:  return "nd"
            case 3:  return "rd"
            default: return "th"
            }
        }
    }

    // MARK: Event lookups (single source of truth for BOTH text and tap —
    // see "Tap Target" below. Each returns the underlying SchoolEvent;
    // the *Secondary text properties just format whatever these find.)

    private var saturdayLookaheadEvent: SchoolEvent? {
        let cal = Calendar.current
        guard let sat = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sat)).first { $0.category != .schedules }
    }

    private var saturdayOrSundayLookaheadEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .schedules && $0.startDate > now }) {
            return event
        }
        guard let sun = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: sun)).first { $0.category != .schedules }
    }

    private var sundayLookaheadEvent: SchoolEvent? {
        let cal = Calendar.current
        let todayKey = DateFormatter.isoDay.string(from: now)
        if let event = store.events(on: todayKey).first(where: { $0.category != .schedules && $0.startDate > now }) {
            return event
        }
        guard let mon = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: mon)).first { $0.category != .schedules }
    }

    private var tomorrowLookaheadEvent: SchoolEvent? {
        let cal = Calendar.current
        guard let tom = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        return store.events(on: DateFormatter.isoDay.string(from: tom)).first { $0.category != .schedules }
    }

    private var saturdaySecondary: String? {
        saturdayLookaheadEvent.map { upcomingEventText($0) }
    }

    private var saturdayOrSundaySecondary: String? {
        saturdayOrSundayLookaheadEvent.map { upcomingEventText($0) }
    }

    private var sundaySecondary: String? {
        if let event = sundayLookaheadEvent { return upcomingEventText(event) }
        let cal = Calendar.current
        guard let mon = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
        let monKey = DateFormatter.isoDay.string(from: mon)
        return scheduleLabelFor(dayKey: monKey).map { "Tomorrow: \($0)" }
    }

    private var tomorrowSecondary: String? {
        tomorrowLookaheadEvent.map { upcomingEventText($0) }
    }

    // MARK: Tap Target
    //
    // Priority: an event shown in the title, then an event shown in the
    // subtitle, then nothing — which falls through to onPillTap (switches
    // to the Events tab, which already auto-scrolls to "now" on appear).
    // That third tier needs no code here at all: it's "go see your current
    // class," and the Day view already does that on its own the moment you
    // land on it. titleEvent/subtitleEvent are deliberately built from the
    // exact same branches as primaryText/secondaryText above (reusing the
    // same lookahead-event properties, not a separate parallel lookup) so
    // tap can never point somewhere the displayed text didn't.

    private var tappableEvent: SchoolEvent? {
        titleEvent ?? subtitleEvent
    }

    private var titleEvent: SchoolEvent? {
        if isSummerWindow { return todayEvent }
        return nil
    }

    private var subtitleEvent: SchoolEvent? {
        if apModeExamDone { return tomorrowLookaheadEvent }
        if isSummerWindow {
            if let event = todayEvent { return event.isAllDay ? nil : event }
            if let event = tomorrowEvent { return event }
            return orientationEvent
        }
        switch state.dayState {
        case .holiday:
            return store.events(on: DateFormatter.isoDay.string(from: now)).first { $0.isHoliday }
        case .afterSchool, .noSchedule:
            let weekday = Calendar.current.component(.weekday, from: now)
            switch weekday {
            case 6:  return saturdayLookaheadEvent
            case 7:  return saturdayOrSundayLookaheadEvent
            case 1:  return sundayLookaheadEvent
            default: return tomorrowLookaheadEvent
            }
        default:
            return nil
        }
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
                self.now = DebugClock.shared.now
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
