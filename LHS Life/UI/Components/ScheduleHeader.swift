//
//  ScheduleHeader.swift
//  LHS Life
//
//  ScheduleHeaderPill — pill with text and progress fill, used on both platforms
//  HeaderActionButton — generic action button paired with the pill
//    • iPhone: lightning bolt → settings (with AP badge)
//    • iPad:   checklist     → homework
//  ScheduleHeader — GlassEffectContainer(pill + action button), platform-agnostic
//  SettingsButton  — standalone, iPad top-right only
//

import SwiftUI

// MARK: - Header Action Button

struct HeaderActionButton: View {
    enum Icon: Equatable {
        case settings(showBadge: Bool)
        case homework
    }

    let icon: Icon
    let action: () -> Void
    var suppressGlass: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Group {
                    switch icon {
                    case .settings:
                        Image("lhs-lightning")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 28, height: 28)
                    case .homework:
                        Image(systemName: "checklist")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.lsPrimary)
                            .frame(width: 28, height: 28)
                    }
                }
                .padding(12)
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
                .ifTrue(!suppressGlass) { $0.modifier(CircleGlassModifier(tint: icon == .homework ? Color.lsPurple : Color.clear)) }

                if case .settings(let showBadge) = icon, showBadge {
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

// MARK: - Settings Button (standalone — iPad top-right only)

struct SettingsButton: View {
    @Binding var showSettings: Bool
    var showBadge: Bool = false

    var body: some View {
        HeaderActionButton(
            icon: .settings(showBadge: showBadge),
            action: { showSettings = true }
        )
    }
}

// MARK: - Glass modifiers

private struct CircleGlassModifier: ViewModifier {
    var tint: Color? = nil
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive().tint(tint), in: Circle())
            
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
                HapticEngine.shared.tap(); onEventTap(event)
            } else if onPillTap != nil {
                HapticEngine.shared.tap(); onPillTap?()
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

// MARK: - Schedule Header
// Pill + action button in a unified glass surface.
// Platform provides the icon and action — component is identical.

struct ScheduleHeader: View {
    let actionIcon: HeaderActionButton.Icon
    let onAction: () -> Void
    var onPillTap: (() -> Void)? = nil
    var onEventTap: ((SchoolEvent) -> Void)? = nil

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: LS.sm) {
                    HStack(spacing: LS.sm) {
                        ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                            .frame(maxWidth: .infinity)
                        HeaderActionButton(icon: actionIcon, action: onAction)
                    }
                }
            } else {
                HStack(spacing: LS.sm) {
                    ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                        .frame(maxWidth: .infinity)
                    HeaderActionButton(icon: actionIcon, action: onAction)
                }
            }
        }
    }
}

// MARK: - Phone Header Row
// iPhone-only. Header pill leading and greedy; trailing toolbar-style
// capsule holds an optional per-tab contextual button (cycle in Events,
// back in the web tabs, none in Lunch) plus settings — one shared capsule,
// like Calendar/Notes, not two separate circles. With no contextual button
// the capsule naturally narrows to just settings.

struct PhoneHeaderRow: View {
    let selectedTab: AppTab
    let cycleLabel: String?
    let onCycle: () -> Void
    let canGoBack: Bool
    let onBack: () -> Void
    let showSettingsBadge: Bool
    let onSettings: () -> Void
    var onPillTap: (() -> Void)? = nil
    var onEventTap: ((SchoolEvent) -> Void)? = nil

    private var contextualSymbol: String? {
        switch selectedTab {
        case .events:                  return zoomSystemIcon(for: cycleLabel)
        case .powerschool, .schoology: return "chevron.left"
        default:                       return nil
        }
    }

    private var contextualEnabled: Bool {
        switch selectedTab {
        case .powerschool, .schoology: return canGoBack
        default:                       return true
        }
    }

    private var contextualAction: () -> Void {
        switch selectedTab {
        case .events:                  return onCycle
        case .powerschool, .schoology: return onBack
        default:                       return {}
        }
    }

    var body: some View {
        let _ = print("[TABNAV] HEADER render — selectedTab=\(selectedTab) symbol=\(contextualSymbol ?? "nil")")
        HStack(spacing: LS.sm) {
            ScheduleHeaderPill(onPillTap: onPillTap, onEventTap: onEventTap)
                .frame(maxWidth: .infinity)
            HeaderTrailingCapsule(
                contextualIcon: contextualSymbol,
                contextualEnabled: contextualEnabled,
                onContextual: contextualAction,
                showSettingsBadge: showSettingsBadge,
                onSettings: onSettings
            )
        }
    }

    private func zoomSystemIcon(for label: String?) -> String {
        switch label {
        case "Month": return "square.grid.2x2.fill"
        case "Year":  return "square.grid.3x3.fill"
        case "Day":   return "calendar.day.timeline.leading"
        default:      return "calendar"
        }
    }
}

// MARK: - Header Trailing Capsule
// One shared toolbar-style capsule (Calendar/Notes pattern): a single
// glassEffect(in: Capsule()) around plain icon buttons on iOS 26+, or one
// shared frosted Capsule background pre-26 — never per-button circles.
// Downsized to standard toolbar scale (32pt buttons vs. the 56pt floating
// buttons this replaced).

struct HeaderTrailingCapsule: View {
    var contextualIcon: String? = nil       // SF Symbol name; nil hides it (e.g. Lunch tab)
    var contextualEnabled: Bool = true
    var onContextual: () -> Void = {}
    let showSettingsBadge: Bool
    let onSettings: () -> Void

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 20

    var body: some View {
        if #available(iOS 26, *) {
            toolbarContent
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            toolbarContent
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 6) {
            if let contextualIcon {
                iconButton(systemName: contextualIcon, enabled: contextualEnabled, action: onContextual)
            }
            settingsButton
        }
        .frame(height: buttonSize)
    }

    private func iconButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(Color.lsPrimary)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }

    private var settingsButton: some View {
        Button {
            HapticEngine.shared.tap()
            onSettings()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(Color.lsPrimary)
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
                if showSettingsBadge {
                    Circle()
                        .fill(Color.lsDestructive)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
}

#Preview {
    ZStack(alignment: .top) {
        Color.lsBackground.ignoresSafeArea()
        ScheduleHeader(
            actionIcon: .settings(showBadge: false),
            onAction: {}
        )
        .environment(CalendarStore())
        .environment(UserSettings.shared)
        .padding(.horizontal, LS.md)
        .padding(.top, LS.sm)
    }
}
