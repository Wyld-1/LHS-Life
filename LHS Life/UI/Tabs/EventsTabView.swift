//
//  EventsTabView.swift
//  LHS Life
//
//  Layout:
//  VStack (background, top-aligned)
//    ├── header clearance + WeekStrip (fixed, never scrolls)
//    └── ScrollView(.vertical)
//          └── HStack(alignment: .top)
//                ├── TimeGutter (pinned left, moves vertically only)
//                └── ScrollView(.horizontal, .viewAligned)
//                      └── HStack of DayColumns (snap per day)
//
//

import SwiftUI

// MARK: - Grid

private enum Grid {
    static let originHour  = 6
    static let endHour     = 22
    static let ppm: CGFloat = 1.1
    static let gutterWidth: CGFloat = 52
    static let totalHeight: CGFloat = CGFloat((endHour - originHour) * 60) * ppm

    static func y(for date: Date, on ref: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour,   from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(h * 60 + m - originHour * 60) * ppm
    }

    static func height(minutes: Double) -> CGFloat { CGFloat(minutes) * ppm }
    static var hourMarks: [Int] { Array(stride(from: originHour, through: endHour, by: 1)) }
}

// MARK: - Root

struct EventsTabView: View {
    @Environment(CalendarStore.self)   private var store
    @Environment(UserSettings.self)    private var settings
    @Environment(CalendarUIState.self) private var uiState

    var body: some View {
        ZStack {
            // All three views stay mounted — opacity switch is instant,
            // no rebuild cost on mode change.
            DayView()
                .opacity(uiState.viewMode == .day ? 1 : 0)
                .allowsHitTesting(uiState.viewMode == .day)
            MonthView()
                .opacity(uiState.viewMode == .month ? 1 : 0)
                .allowsHitTesting(uiState.viewMode == .month)
            YearView()
                .opacity(uiState.viewMode == .year ? 1 : 0)
                .allowsHitTesting(uiState.viewMode == .year)
        }
        .simultaneousGesture(
            MagnificationGesture(minimumScaleDelta: 0.2)
                .onEnded { scale in
                    if scale < 0.85 { uiState.zoomOut() }
                    else if scale > 1.15 {
                        withAnimation(.lsSnappy) {
                            switch uiState.viewMode {
                            case .year:  uiState.viewMode = .month
                            case .month: uiState.viewMode = .day
                            case .day:   break
                            }
                        }
                    }
                }
        )
    }
}

// MARK: - Day View (existing calendar logic, renamed)

private struct DayView: View {
    @Environment(CalendarStore.self)   private var store
    @Environment(UserSettings.self)    private var settings
    @Environment(CalendarUIState.self) private var uiState

    private let cal      = Calendar.current
    private let dayRange = -365...365

    private var today: Date { cal.startOfDay(for: Date()) }

    private func dayDate(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today) ?? today
    }
    private func offsetFor(_ date: Date) -> Int {
        cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = geo.size.width - Grid.gutterWidth
            VStack(spacing: 0) {
                // Fixed header
                Color.clear.frame(height: LS.contentTopInset)
                WeekStrip(selectedDate: Binding(
                    get: { uiState.selectedDate },
                    set: { uiState.selectedDate = $0 }
                ))
                    .padding(.bottom, LS.xs)

                // All-day strip — collapses when empty
                AllDayStrip(store: store, date: uiState.selectedDate, columnWidth: geo.size.width - Grid.gutterWidth)

                ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    let anchorY = max(0, Grid.y(for: Date(), on: Date()) - Grid.ppm * 60)
                    let eventAnchorY: CGFloat = {
                        guard let event = uiState.scrollToEvent else { return 0 }
                        return max(0, Grid.y(for: event.startDate, on: event.startDate) - Grid.ppm * 60)
                    }()
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(width: 1, height: anchorY)
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("now-anchor")
                        // Event anchor — repositions when scrollToEvent changes
                        if let event = uiState.scrollToEvent {
                            Color.clear
                                .frame(width: 1, height: max(0, eventAnchorY - anchorY))
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("event-anchor")
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: geo.size.width,
                           height: Grid.totalHeight + LS.tabBarHeight,
                           alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: 0) {
                                // Time gutter — outside horizontal scroll, never moves sideways
                                TimeGutter(columnWidth: columnWidth, selectedDate: uiState.selectedDate)
                                    .frame(width: Grid.gutterWidth)

                                // Day columns — horizontal snap scroll
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 0) {
                                        ForEach(dayRange, id: \.self) { offset in
                                            DayColumn(
                                                date:     dayDate(offset),
                                                store:    store,
                                                settings: settings,
                                                width:    columnWidth
                                            )
                                            .id(offset)
                                            .containerRelativeFrame(.horizontal)
                                        }
                                    }
                                    .scrollTargetLayout()
                                }
                                .scrollTargetBehavior(.viewAligned)
                                .scrollPosition(id: Binding(
                                    get: { offsetFor(uiState.selectedDate) },
                                    set: { newOffset in
                                        guard let newOffset, dayRange.contains(newOffset) else { return }
                                        let d = dayDate(newOffset)
                                        if !cal.isDate(d, inSameDayAs: uiState.selectedDate) {
                                            uiState.selectedDate = d
                                            HapticEngine.shared.tick()
                                        }
                                    }
                                ))
                            }
                        }
                        .padding(.top, LS.md)
                        .frame(width: geo.size.width,
                               height: Grid.totalHeight + LS.tabBarHeight - LS.md,
                               alignment: .topLeading)
                    }
                }
                .onAppear {
                    proxy.scrollTo("now-anchor", anchor: .top)
                }
                .onChange(of: uiState.scrollToNow) { _, _ in
                    withAnimation(.lsSnappy) {
                        proxy.scrollTo("now-anchor", anchor: .top)
                    }
                }
                .onChange(of: uiState.scrollToEvent) { _, event in
                    guard event != nil else { return }
                    // Small delay so selectedDate has time to snap the horizontal scroll
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.lsSnappy) {
                            proxy.scrollTo("event-anchor", anchor: .top)
                        }
                    }
                }
                } // ScrollViewReader
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.lsBackground)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Time Gutter
// Pinned to the left of the vertical scroll.
// Hour labels + grid lines that extend into the day column area.
// columnWidth passed in so lines extend the full day column width.

private struct TimeGutter: View {
    let columnWidth: CGFloat
    let selectedDate: Date

    @State private var now: Date = Date()
    @State private var timer: Timer?

    private var dotY: CGFloat { Grid.y(for: now, on: now) }
    private var showDot: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid lines — extend rightward into day columns
            ForEach(Grid.hourMarks, id: \.self) { hour in
                let y = CGFloat((hour - Grid.originHour) * 60) * Grid.ppm
                Rectangle()
                    .fill(Color.lsTertiary.opacity(0.18))
                    .frame(width: Grid.gutterWidth + columnWidth, height: 0.5)
                    .offset(y: y)
            }

            // Hour labels
            ForEach(Grid.hourMarks, id: \.self) { hour in
                let number = hour == 0 ? "12" : hour <= 12 ? "\(hour)" : "\(hour - 12)"
                let suffix = hour < 12 ? "AM" : "PM"
                let y = CGFloat((hour - Grid.originHour) * 60) * Grid.ppm
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
                .offset(y: y - 9)
            }

            // Time dot — visible only when selected day is today
            if showDot {
                Circle()
                    .fill(Color.lsDestructive)
                    .frame(width: 11, height: 11)
                    .shadow(color: Color.lsDestructive, radius: 2)
                    .frame(width: Grid.gutterWidth, alignment: .trailing)
                    .offset(y: dotY + 1.5 - 5.5)
                    .animation(.linear(duration: 1), value: now)
            }
        }
        .frame(width: Grid.gutterWidth, height: Grid.totalHeight, alignment: .topLeading)
        .onAppear {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task { @MainActor in self.now = Date() }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }
}

// MARK: - Day Column

private struct DayColumn: View {
    let date: Date
    let store: CalendarStore
    let settings: UserSettings
    let width: CGFloat

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var dayKey: String { DateFormatter.isoDay.string(from: date) }
    private var schedule: BellSchedule? { store.bellSchedules[dayKey] }
    private var events: [SchoolEvent] { store.events(on: dayKey) }

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

    private var timedEvents: [SchoolEvent] {
        events.filter { $0.category != .bellSchedule && !$0.isAllDay }
    }

    // Greedy column assignment for timed events, period-aware.
    // Periods implicitly own column 0 for their full duration.
    // Events that overlap any period start at column 1;
    // events that don't overlap any period start at column 0.
    private var layoutEvents: [(event: SchoolEvent, col: Int, totalCols: Int)] {
        let sorted = timedEvents.sorted { $0.startDate < $1.startDate }

        // Build a list of occupied time ranges per column.
        // Column 0 is pre-seeded with all visible period spans.
        var colEnds: [Date] = []

        // Pre-seed column 0 with period blocks so events can't land there if overlapping
        let periodSpans = visiblePeriods.map { ($0.start, $0.end) }
        if !periodSpans.isEmpty {
            // Column 0 is "busy" whenever any period is active.
            // We track the max end of any period overlapping each event at assignment time.
            colEnds.append(Date.distantPast) // placeholder; overlap checked below
        }

        var assignments: [(event: SchoolEvent, col: Int)] = []

        for event in sorted {
            // Check if this event overlaps any period
            let overlappsPeriod = periodSpans.contains { start, end in
                event.startDate < end && event.endDate > start
            }

            if overlappsPeriod {
                // Must go to column 1+
                // Find first column >= 1 that's free
                if colEnds.count < 2 { colEnds.append(Date.distantPast) }
                var placed = false
                for i in 1..<colEnds.count {
                    if event.startDate >= colEnds[i] {
                        colEnds[i] = event.endDate
                        assignments.append((event, i))
                        placed = true
                        break
                    }
                }
                if !placed {
                    colEnds.append(event.endDate)
                    assignments.append((event, colEnds.count - 1))
                }
            } else {
                // No period overlap — greedy from column 0
                var placed = false
                for i in 0..<colEnds.count {
                    if event.startDate >= colEnds[i] {
                        colEnds[i] = event.endDate
                        assignments.append((event, i))
                        placed = true
                        break
                    }
                }
                if !placed {
                    if colEnds.isEmpty {
                        colEnds.append(event.endDate)
                        assignments.append((event, 0))
                    } else {
                        colEnds.append(event.endDate)
                        assignments.append((event, colEnds.count - 1))
                    }
                }
            }
        }

        // Second pass: total columns in each event's overlapping group,
        // also counting column 0 as occupied if a period overlaps this event.
        return assignments.map { item in
            let eventCols = assignments.filter { other in
                other.event.startDate < item.event.endDate &&
                other.event.endDate > item.event.startDate
            }.map(\.col)

            let periodOccupiesCol0 = periodSpans.contains { start, end in
                item.event.startDate < end && item.event.endDate > start
            }

            let allCols = periodOccupiesCol0
                ? ([0] + eventCols)
                : eventCols
            let totalCols = (allCols.max() ?? 0) + 1
            return (item.event, item.col, totalCols)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: width, height: Grid.totalHeight)

            // Period blocks — narrowed when a timed event runs alongside
            ForEach(visiblePeriods, id: \.period.id) { item in
                let hasOverlap = layoutEvents.contains { ev in
                    ev.col > 0 &&
                    ev.event.startDate < item.end &&
                    ev.event.endDate > item.start
                }
                let effectiveWidth = hasOverlap ? (width / 2) - LS.sm : width
                PeriodBlock(
                    period:   item.period,
                    start:    item.start,
                    end:      item.end,
                    date:     date,
                    now:      now,
                    isToday:  isToday,
                    settings: settings
                )
                .padding(.leading, 4)
                .padding(.trailing, LS.sm)
                .frame(width: effectiveWidth)
                .offset(y: Grid.y(for: item.start, on: date))
            }

            // Timed event blocks with overlap layout
            ForEach(layoutEvents, id: \.event.id) { item in
                let colWidth = (width - LS.sm) / CGFloat(item.totalCols)
                let xOffset  = CGFloat(item.col) * colWidth + (item.col > 0 ? 2 : 4)
                EventBlock(event: item.event)
                    .frame(width: colWidth - (item.col > 0 ? 2 : 0))
                    .offset(x: xOffset, y: Grid.y(for: item.event.startDate, on: date))
            }

            // Time scrubber capsule — only on today
            if isToday {
                HStack(spacing: 0) {
                    Capsule()
                        .fill(Color.lsDestructive)
                        .frame(height: 3)
                        .padding(.trailing, LS.sm)
                }
                .shadow(color: Color.lsDestructive, radius: 2)
                .frame(width: width, alignment: .leading)
                .offset(y: Grid.y(for: now, on: date))
                .animation(.linear(duration: 1), value: now)
            }
        }
        .frame(width: width, height: Grid.totalHeight, alignment: .topLeading)
        .clipped()
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
    private var color: Color { config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary }
    private var displayName: String { config?.displayName ?? period.name }
    private var isCurrent: Bool { isToday && now >= start && now < end }

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            Text(displayName)
                .font(.system(size: blockHeight > 28 ? 12 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.vertical, 3)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.3))
        )
    }
}

// MARK: - Event Block

private struct EventBlock: View {
    let event: SchoolEvent

    private var blockHeight: CGFloat {
        max(Grid.height(minutes: event.endDate.timeIntervalSince(event.startDate) / 60), 18)
    }
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
        HStack(spacing: 0) {
            Capsule()
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 3)
                .padding(.leading, 0)
                .padding(.trailing, 4)
            Text(event.title)
                .font(.system(size: blockHeight > 28 ? 12 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(blockHeight > 28 ? 2 : 1)
                .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.18))
        )
        .padding(.trailing, 2)
    }
}

// MARK: - All-Day Strip

private struct AllDayStrip: View {
    let store: CalendarStore
    let date: Date
    let columnWidth: CGFloat

    private var dayKey: String { DateFormatter.isoDay.string(from: date) }
    private var allDayEvents: [SchoolEvent] {
        store.events(on: dayKey).filter { $0.isAllDay && $0.category != .bellSchedule }
    }

    private func color(for event: SchoolEvent) -> Color {
        switch event.category {
        case .athletic: return Color.lsGold
        case .liturgy:  return Color.lsBlue
        case .academic: return Color.lsSuccess
        case .holiday:  return Color.lsOrange
        default:        return Color.lsSecondary
        }
    }

    var body: some View {
        if !allDayEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LS.xs) {
                    ForEach(allDayEvents, id: \.id) { event in
                        let c = color(for: event)
                        Text(event.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(c)
                            .lineLimit(1)
                            .padding(.horizontal, LS.sm)
                            .padding(.vertical, 5)
                            .background(c.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
                    }
                }
                .padding(.horizontal, Grid.gutterWidth)
                .padding(.vertical, LS.xs)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.lsTertiary.opacity(0.2))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Week Strip

struct WeekStrip: View {
    @Binding var selectedDate: Date

    private let cal = Calendar.current
    @State private var weekOffset: Int = 0

    private func sunday(weekOffset: Int) -> Date? {
        let today = cal.startOfDay(for: Date())
        let wd    = cal.component(.weekday, from: today)
        let toSun = -(wd - 1)
        guard let thisSunday = cal.date(byAdding: .day, value: toSun, to: today) else { return nil }
        // Use .day * 7 instead of .weekOfYear to avoid DST boundary issues
        return cal.date(byAdding: .day, value: weekOffset * 7, to: thisSunday)
    }

    private func days(for weekOffset: Int) -> [Date] {
        guard let sun = sunday(weekOffset: weekOffset) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: sun) }
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
            return sunday(weekOffset: weekOffset).map { "Week of \(f.string(from: $0))" } ?? ""
        }
    }

    private func offsetFor(_ date: Date) -> Int {
        guard let thisSunday = sunday(weekOffset: 0) else { return 0 }
        let wd    = cal.component(.weekday, from: date)
        let toSun = -(wd - 1)
        let selSunday = cal.date(byAdding: .day, value: toSun,
                                 to: cal.startOfDay(for: date)) ?? date
        return cal.dateComponents([.weekOfYear], from: thisSunday, to: selSunday).weekOfYear ?? 0
    }

    var body: some View {
        VStack(spacing: LS.sm) {
            Text(weekLabel(for: weekOffset))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lsSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LS.md)
                .animation(.lsSnappy, value: weekOffset)

            TabView(selection: $weekOffset) {
                ForEach(-52...52, id: \.self) { offset in
                    HStack(spacing: 0) {
                        ForEach(days(for: offset), id: \.self) { day in
                            DayChip(date: day,
                                    isSelected: cal.isDate(day, inSameDayAs: selectedDate))
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
            .onChange(of: weekOffset) { oldOffset, newOffset in
                let newDays = days(for: newOffset)
                let alreadyInWeek = newDays.contains { cal.isDate($0, inSameDayAs: selectedDate) }
                if !alreadyInWeek {
                    // Find the same weekday in the new week
                    let currentWeekday = cal.component(.weekday, from: selectedDate)
                    let target = newDays.first {
                        cal.component(.weekday, from: $0) == currentWeekday
                    } ?? (newOffset < oldOffset ? newDays.last : newDays.first)
                    if let target {
                        withAnimation(.lsSnappy) { selectedDate = target }
                        HapticEngine.shared.tick()
                    }
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
    private var isWeekend: Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

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
                    .foregroundStyle(
                        isSelected ? .white :
                        isToday    ? Color.lsBlue :
                        isWeekend  ? Color.lsSecondary :
                                     Color.lsPrimary
                    )
            }
        }
        .padding(.vertical, LS.xs)
    }

    private var dayName: String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date).uppercased()
    }
    private var dayNum: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }
}

// MARK: - Segmented Pill

private struct SegmentedPill: View {
    let colors: [Color]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .frame(width: width, height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Month View

private struct MonthView: View {
    @Environment(CalendarStore.self)   private var store
    @Environment(CalendarUIState.self) private var uiState

    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private let monthRange = -24...24  // months relative to current

    // Derive displayed month from selectedDate
    private var displayedYear: Int  { cal.component(.year,  from: uiState.selectedDate) }
    private var displayedMonth: Int { cal.component(.month, from: uiState.selectedDate) }

    private func firstOfMonth(offset: Int) -> Date {
        let base = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        return cal.date(byAdding: .month, value: offset, to: base)!
    }

    private func monthOffset(for date: Date) -> Int {
        let baseComps = cal.dateComponents([.year, .month], from: today)
        let dateComps = cal.dateComponents([.year, .month], from: date)
        let baseDate  = cal.date(from: baseComps)!
        let targetDate = cal.date(from: dateComps)!
        return cal.dateComponents([.month], from: baseDate, to: targetDate).month ?? 0
    }

    @State private var scrollOffset: Int = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear.frame(height: LS.contentTopInset)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(monthRange, id: \.self) { offset in
                                MonthGrid(
                                    firstOfMonth: firstOfMonth(offset: offset),
                                    selectedDate: uiState.selectedDate,
                                    store: store,
                                    onTap: { date in uiState.zoomIn(to: date) }
                                )
                                .id(offset)
                            }
                        }
                    }
                    .onAppear {
                        let offset = monthOffset(for: uiState.selectedDate)
                        proxy.scrollTo(offset, anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.lsBackground)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Month Grid (one calendar month)

private struct MonthGrid: View {
    let firstOfMonth: Date
    let selectedDate: Date
    let store: CalendarStore
    let onTap: (Date) -> Void

    private let cal = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private let dayWidth: CGFloat = UIScreen.main.bounds.width / 7

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: firstOfMonth)
    }
    private var yearTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: firstOfMonth)
    }
    private var isCurrentYear: Bool {
        cal.component(.year, from: firstOfMonth) == cal.component(.year, from: today)
    }

    private var days: [Date?] {
        // Pad to start on Sunday
        let wd = cal.component(.weekday, from: firstOfMonth) - 1
        var result: [Date?] = Array(repeating: nil, count: wd)
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)!
        for d in range {
            result.append(cal.date(byAdding: .day, value: d - 1, to: firstOfMonth))
        }
        // Pad to complete last row
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Month header
            HStack(alignment: .firstTextBaseline, spacing: LS.xs) {
                Text(monthTitle)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        cal.component(.month, from: firstOfMonth) == cal.component(.month, from: today) &&
                        cal.component(.year,  from: firstOfMonth) == cal.component(.year,  from: today)
                            ? Color.lsBlue : Color.lsPrimary
                    )
                if !isCurrentYear {
                    Text(yearTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.lsSecondary)
                }
            }
            .padding(.horizontal, LS.md)
            .padding(.top, LS.md)
            .padding(.bottom, LS.xs)

            // Divider under header
            Rectangle()
                .fill(Color.lsTertiary.opacity(0.2))
                .frame(height: 0.5)

            // Day-of-week headers (only on first month or always)
            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lsTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, LS.xs)

            // Day cells
            let chunks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0+7, days.count)]) }
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            MonthDayCell(
                                date: day,
                                isSelected: cal.isDate(day, inSameDayAs: selectedDate),
                                isToday: cal.isDate(day, inSameDayAs: today),
                                summary: store.summary(for: DateFormatter.isoDay.string(from: day)),
                                onTap: { onTap(day) }
                            )
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let summary: DaySummary
    let onTap: () -> Void

    private let cal = Calendar.current
    private var isWeekend: Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.lsBlue : Color.clear)
                    .frame(width: 28, height: 28)
                if isToday && !isSelected {
                    Circle()
                        .strokeBorder(Color.lsBlue, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 14,
                                  weight: isToday || isSelected ? .bold : .regular,
                                  design: .rounded))
                    .foregroundStyle(
                        isSelected ? .white :
                        isToday    ? Color.lsBlue :
                        isWeekend  ? Color.lsSecondary :
                                     Color.lsPrimary
                    )
            }

            // Segmented pill — collapses when no events
            if !summary.isEmpty {
                SegmentedPill(
                    colors: summary.pillColors,
                    width: summary.pillColors.count == 1 ? 20 : CGFloat(summary.pillColors.count) * 10,
                    height: 4
                )
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticEngine.shared.tick()
            onTap()
        }
    }
}

// MARK: - Year View

private struct YearView: View {
    @Environment(CalendarStore.self)   private var store
    @Environment(CalendarUIState.self) private var uiState

    private let cal   = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private let yearRange = -3...3

    private func year(for offset: Int) -> Int {
        cal.component(.year, from: today) + offset
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Color.clear.frame(height: LS.contentTopInset)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: LS.xl) {
                            ForEach(yearRange, id: \.self) { offset in
                                YearGrid(year: year(for: offset), store: store) { date in
                                    uiState.zoomIn(to: date)
                                }
                                .id(offset)
                            }
                        }
                        .padding(.bottom, LS.tabBarHeight + LS.lg)
                    }
                    .onAppear {
                        proxy.scrollTo(0, anchor: .top) // current year is offset 0
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.lsBackground)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Year Grid (one full year, 3-column)

private struct YearGrid: View {
    let year: Int
    let store: CalendarStore
    let onTap: (Date) -> Void

    private let cal   = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())
    private let cols  = 3

    private var isCurrentYear: Bool { year == cal.component(.year, from: today) }

    private func firstOfMonth(_ month: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LS.md) {
            // Year label
            Text(String(format: "%d", year))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrentYear ? Color.lsBlue : Color.lsPrimary)
                .padding(.horizontal, LS.md)

            Rectangle()
                .fill(Color.lsTertiary.opacity(0.2))
                .frame(height: 0.5)

            // 4 rows × 3 months
            let months = Array(1...12)
            let rows = stride(from: 0, to: 12, by: cols).map { Array(months[$0..<min($0+cols, 12)]) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: LS.sm) {
                    ForEach(row, id: \.self) { month in
                        MiniMonthView(
                            firstOfMonth: firstOfMonth(month),
                            store: store,
                            today: today,
                            onTap: onTap
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, LS.md)
            }
        }
    }
}

// MARK: - Mini Month (year view cell)

private struct MiniMonthView: View {
    let firstOfMonth: Date
    let store: CalendarStore
    let today: Date
    let onTap: (Date) -> Void

    private let cal = Calendar.current
    private let daySize: CGFloat = 18

    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: firstOfMonth)
    }
    private var isCurrentMonth: Bool {
        cal.component(.month, from: firstOfMonth) == cal.component(.month, from: today) &&
        cal.component(.year,  from: firstOfMonth) == cal.component(.year,  from: today)
    }
    private var days: [Date?] {
        let wd = cal.component(.weekday, from: firstOfMonth) - 1
        var result: [Date?] = Array(repeating: nil, count: wd)
        let range = cal.range(of: .day, in: .month, for: firstOfMonth)!
        for d in range { result.append(cal.date(byAdding: .day, value: d - 1, to: firstOfMonth)) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(monthName)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrentMonth ? Color.lsBlue : Color.lsSecondary)

            let chunks = stride(from: 0, to: days.count, by: 7)
                .map { Array(days[$0..<min($0+7, days.count)]) }
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let isToday = cal.isDate(day, inSameDayAs: today)
                            let summary = store.summary(for: DateFormatter.isoDay.string(from: day))
                            ZStack {
                                if isToday {
                                    Circle()
                                        .fill(Color.lsBlue)
                                        .frame(width: daySize, height: daySize)
                                }
                                Text("\(cal.component(.day, from: day))")
                                    .font(.system(size: 8, weight: isToday ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(isToday ? .white : Color.lsPrimary)
                                // dot indicator at bottom of cell
                                if !summary.isEmpty {
                                    VStack {
                                        Spacer()
                                        Circle()
                                            .fill(summary.pillColors.first ?? Color.lsTertiary)
                                            .frame(width: 3, height: 3)
                                    }
                                }
                            }
                            .frame(width: daySize, height: daySize)
                            .contentShape(Rectangle())
                            .onTapGesture { HapticEngine.shared.tick(); onTap(day) }
                        } else {
                            Color.clear.frame(width: daySize, height: daySize)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    EventsTabView()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
        .environment(CalendarUIState())
}
