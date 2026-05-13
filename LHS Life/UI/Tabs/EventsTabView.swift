//
//  EventsTabView.swift
//  LHS Life
//
//  Architecture:
//  — TabView(.page) handles horizontal day swiping with native carousel feel.
//  — Each page is a ScrollView containing the day canvas.
//  — The day canvas is a single ZStack where gutter labels, grid lines,
//    period blocks, and events all share the same coordinate space.
//    Everything is positioned with the same Grid.y() function from a
//    fixed 5 AM origin — no HStack, no misaligned frames.
//

import SwiftUI

// MARK: - Grid

private enum Grid {
    static let originHour = 6
    static let endHour    = 22

    // 0.75pt per minute
    static let ppm: CGFloat = 1.1

    static let gutterWidth: CGFloat = 52
    static let totalHeight: CGFloat = CGFloat((endHour - originHour) * 60) * ppm

    static func y(for date: Date, on ref: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour,   from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(h * 60 + m - originHour * 60) * ppm
    }

    static func height(minutes: Double) -> CGFloat {
        CGFloat(minutes) * ppm
    }

    static var hourMarks: [Int] {
        Array(stride(from: originHour, through: endHour, by: 1))
    }

    static func hourLabel(_ h: Int) -> String {
        if h == 0  { return "12 AM" }
        if h < 12  { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }
}

// MARK: - Root

struct EventsTabView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    // Page index relative to today (0 = today, 1 = tomorrow, -1 = yesterday)
    @State private var pageOffset: Int = 0
    // Derived selected date — kept in sync with pageOffset
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private let today = Calendar.current.startOfDay(for: Date())
    private let cal   = Calendar.current

    // Range of pages available: ±60 days
    private let range = -60...60

    private func date(for offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today) ?? today
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header — pill clearance + week strip
            Color.clear.frame(height: LS.contentTopInset)

            WeekStrip(selectedDate: $selectedDate, onLabelTap: {})
                .padding(.bottom, LS.xs)

            // Horizontal page carousel
            TabView(selection: $pageOffset) {
                ForEach(range, id: \.self) { offset in
                    DayPage(
                        date:     date(for: offset),
                        store:    store,
                        settings: settings
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.lsBackground)
        .ignoresSafeArea(edges: .top)
        // Keep selectedDate and pageOffset in sync
        .onChange(of: pageOffset) { _, offset in
            let d = date(for: offset)
            if !cal.isDate(d, inSameDayAs: selectedDate) {
                withAnimation(.lsSnappy) { selectedDate = d }
                HapticEngine.shared.tick()
            }
        }
        .onChange(of: selectedDate) { _, d in
            let offset = cal.dateComponents([.day], from: today, to: d).day ?? 0
            if offset != pageOffset {
                withAnimation(.lsSnappy) { pageOffset = offset }
            }
        }
    }
}

// MARK: - Day Page
// One page of the carousel. Contains the vertical ScrollView.

private struct DayPage: View {
    let date: Date
    let store: CalendarStore
    let settings: UserSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                let dayKey   = DateFormatter.isoDay.string(from: date)
                let schedule = store.bellSchedules[dayKey]
                let events   = store.events(on: dayKey)

                DayCanvas(
                    date:     date,
                    schedule: schedule,
                    events:   events,
                    settings: settings
                )
                .padding(.top, LS.sm)

                Color.clear.frame(height: LS.tabBarHeight + LS.lg)
            }
        }
    }
}

// MARK: - Day Canvas
//
// Single ZStack — gutter, grid lines, periods, events all share
// the same coordinate space. Grid.y() places everything correctly.

private struct DayCanvas: View {
    let date: Date
    let schedule: BellSchedule?
    let events: [SchoolEvent]
    let settings: UserSettings

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var visiblePeriods: [(period: Period, start: Date, end: Date)] {
        guard let s = schedule else { return [] }
        return s.periods.compactMap { p -> (Period, Date, Date)? in
            if let num = periodNum(p.name),
               settings.config(for: num)?.isEnabled == false { return nil }
            guard let start = p.startDate(on: s.date),
                  let end   = p.endDate(on: s.date) else { return nil }
            return (p, start, end)
        }.sorted { $0.1 < $1.1 }
    }

    private var nonBellEvents: [SchoolEvent] {
        events.filter { $0.category != .bellSchedule && !$0.isAllDay }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {

            // 1. Canvas height anchor
            Color.clear
                .frame(width: Grid.gutterWidth, height: Grid.totalHeight)

            // 2. Hour grid lines — full width, same y-origin
            ForEach(Grid.hourMarks, id: \.self) { hour in
                Capsule()
                    .fill(Color.lsTertiary.opacity(0.2))
                    .frame(height: 1.5)
                    .padding(.leading, Grid.gutterWidth)
                    .padding(.trailing, LS.md)
                    .offset(y: CGFloat((hour - Grid.originHour) * 60) * Grid.ppm)
            }

            ForEach(Grid.hourMarks, id: \.self) { hour in
                let number = hour == 0 ? "12" : hour <= 12 ? "\(hour)" : "\(hour - 12)"
                let suffix = hour < 12 ? "AM" : "PM"
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Spacer()
                    Text(number)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(suffix)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lsTertiary)
                }
                .frame(width: Grid.gutterWidth - 6)
                .offset(y: CGFloat((hour - Grid.originHour) * 60) * Grid.ppm - 9)
            }

            ForEach(visiblePeriods, id: \.period.id) { item in
                PeriodBlock(
                    period:  item.period,
                    start:   item.start,
                    end:     item.end,
                    date:    date,
                    now:     now,
                    isToday: isToday,
                    settings: settings
                )
                .padding(.leading, Grid.gutterWidth + 4)
                .padding(.trailing, LS.md)
                .offset(y: Grid.y(for: item.start, on: date))
            }

            // 5. Event pills — right edge
            ForEach(nonBellEvents, id: \.id) { event in
                EventPill(event: event)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, LS.md)
                    .offset(y: Grid.y(for: event.startDate, on: date) - 4)
            }

            // 6. Current time scrubber
            if isToday {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color.lsDestructive)
                        .frame(width: 11, height: 11)
                        .offset(x: Grid.gutterWidth)
                    Capsule()
                        .fill(Color.lsDestructive)
                        .frame(height: 3)
                        .padding(.leading, Grid.gutterWidth - 4)
                        .padding(.trailing, LS.md)
                }
                .shadow(color: Color.lsDestructive, radius: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: Grid.y(for: now, on: date))
                .animation(.linear(duration: 1), value: now)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Grid.totalHeight)
        .onAppear {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in self.now = Date() }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func periodNum(_ name: String) -> Int? {
        let p = name.split(separator: " ")
        guard p.count == 2, p[0].lowercased() == "period" else { return nil }
        return Int(p[1])
    }
}

// MARK: - Period Block
// Apple Calendar style: colored rounded rect at low opacity, opaque sidebar, colored text.
// No time label inside — the gutter handles time, the block handles identity.

private struct PeriodBlock: View {
    let period: Period
    let start: Date
    let end: Date
    let date: Date
    let now: Date
    let isToday: Bool
    let settings: UserSettings

    private var blockHeight: CGFloat {
        Grid.height(minutes: end.timeIntervalSince(start) / 60)
    }

    private var num: Int? {
        let p = period.name.split(separator: " ")
        guard p.count == 2, p[0].lowercased() == "period" else { return nil }
        return Int(p[1])
    }

    private var config: PeriodConfig? { num.flatMap { settings.config(for: $0) } }

    private var color: Color {
        config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
    }

    private var displayName: String { config?.displayName ?? period.name }

    private var isCurrent: Bool { isToday && now >= start && now < end }
    private var isPast: Bool    { isToday && now >= end }

    var body: some View {
        HStack(spacing: 0) {
            // Opaque sidebar capsule
            Capsule()
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)

            // Period name in matching color
            Text(displayName)
                .font(.system(
                    size: blockHeight > 28 ? 12 : 10,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.vertical, 3)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: blockHeight)
        // Colored rounded rect background at low opacity
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.3))
        )
    }
}

// MARK: - Event Pill

private struct EventPill: View {
    let event: SchoolEvent

    private var color: Color {
        switch event.category {
        case .athletic: return Color.lsGold
        case .liturgy:  return Color.lsBlue
        case .academic: return Color.lsSuccess
        case .holiday:  return Color.lsOrange
        default:        return Color.lsSecondary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Week Strip

struct WeekStrip: View {
    @Binding var selectedDate: Date
    let onLabelTap: () -> Void

    private let cal = Calendar.current
    @State private var weekOffset: Int = 0

    // Monday of a given week offset from this week
    private func monday(weekOffset: Int) -> Date? {
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today)
        let toMon = wd == 1 ? -6 : -(wd - 2)
        guard let thisMonday = cal.date(byAdding: .day, value: toMon, to: today) else { return nil }
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday)
    }

    private func days(for weekOffset: Int) -> [Date] {
        guard let mon = monday(weekOffset: weekOffset) else { return [] }
        return (0..<5).compactMap { cal.date(byAdding: .day, value: $0, to: mon) }
    }

    private func weekLabel(for weekOffset: Int) -> String {
        switch weekOffset {
        case -4: return "4 Weeks Ago"
        case -3: return "3 Weeks Ago"
        case -2: return "2 Weeks Ago"
        case -1: return "Last Week"
        case  0: return "This Week"
        case  1: return "Next Week"
        case  2: return "In 2 Weeks"
        case  3: return "In 3 Weeks"
        case  4: return "In 4 Weeks"
        default:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return monday(weekOffset: weekOffset).map { "Week of \(f.string(from: $0))" } ?? ""
        }
    }

    // Sync weekOffset from selectedDate
    private func offsetFor(_ date: Date) -> Int {
        guard let thisMonday = monday(weekOffset: 0) else { return 0 }
        let selMonday: Date
        let wd = cal.component(.weekday, from: date)
        let toMon = wd == 1 ? -6 : -(wd - 2)
        selMonday = cal.date(byAdding: .day, value: toMon, to: cal.startOfDay(for: date)) ?? date
        return cal.dateComponents([.weekOfYear], from: thisMonday, to: selMonday).weekOfYear ?? 0
    }

    var body: some View {
        VStack(spacing: LS.sm) {
            Button(action: onLabelTap) {
                HStack(spacing: 4) {
                    Text(weekLabel(for: weekOffset))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lsSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lsTertiary)
                    Spacer()
                }
                .padding(.horizontal, LS.md)
            }
            .buttonStyle(.plain)
            .animation(.lsSnappy, value: weekOffset)

            // Week carousel
            TabView(selection: $weekOffset) {
                ForEach(-8...8, id: \.self) { offset in
                    HStack(spacing: 0) {
                        ForEach(days(for: offset), id: \.self) { day in
                            DayChip(
                                date: day,
                                isSelected: cal.isDate(day, inSameDayAs: selectedDate)
                            )
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticEngine.shared.tick()
                                withAnimation(.lsSnappy) { selectedDate = day }
                            }
                        }
                    }
                    .padding(.horizontal, LS.md)
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 64)
            // When week strip swipes, jump selectedDate to that week's Monday
            // (or today if this week, else Monday)
            .onChange(of: weekOffset) { _, offset in
                let newDays = days(for: offset)
                // If selected date is already in this week, keep it. Otherwise jump to Monday.
                let alreadyInWeek = newDays.contains { cal.isDate($0, inSameDayAs: selectedDate) }
                if !alreadyInWeek, let first = newDays.first {
                    withAnimation(.lsSnappy) { selectedDate = first }
                    HapticEngine.shared.tick()
                }
            }

            Rectangle()
                .fill(Color.lsTertiary.opacity(0.2))
                .frame(height: 0.5)
        }
        .onAppear { weekOffset = offsetFor(selectedDate) }
        .onChange(of: selectedDate) { _, d in
            let newOffset = offsetFor(d)
            if newOffset != weekOffset {
                withAnimation(.lsSnappy) { weekOffset = newOffset }
            }
        }
    }
}

// MARK: - Day Chip

private struct DayChip: View {
    let date: Date
    let isSelected: Bool

    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayName)
                .font(.lsLabel)
                .foregroundStyle(isSelected ? Color.lsBlue : Color.lsTertiary)
            ZStack {
                Circle()
                    .fill(isSelected ? Color.lsBlue : Color.clear)
                    .frame(width: 30, height: 30)
                if isToday && !isSelected {
                    Circle()
                        .strokeBorder(Color.lsBlue, lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                }
                Text(dayNum)
                    .font(.system(size: 15,
                                  weight: isToday || isSelected ? .bold : .regular,
                                  design: .rounded))
                    .foregroundStyle(isSelected ? .white : isToday ? Color.lsBlue : Color.lsPrimary)
            }
        }
        .padding(.vertical, LS.xs)
    }

    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private var dayNum: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }
}

#Preview {
    EventsTabView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
