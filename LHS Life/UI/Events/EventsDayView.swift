//
//  EventsDayView.swift
//  LHS Life
//
//  Pure canvas — no GeometryReader, no internal ScrollView.
//  The parent ScrollView in EventsTabView handles all scrolling.
//
//  Layout:
//    • All-day pill row + divider
//    • VStack of hour rows (each hourRowHeight tall)
//      Each row has a left-padded time label and a full-width rule.
//    • Event blocks overlaid on the hour grid using absolute y-offsets
//

import SwiftUI

struct EventsDayView: View {

    let date:     Date
    let schedule: BellSchedule?
    let events:   [SchoolEvent]
    let settings: UserSettings

    private let gutterPad:     CGFloat = 44   // left padding for time labels
    private let hourRowHeight: CGFloat = 64
    private let eventInset:    CGFloat = 48   // x where event blocks start (gutter + small gap)

    private var timeRange: (start: Int, end: Int) {
        var earliest = 7
        var latest   = 16
        if let schedule {
            for p in schedule.periods {
                if let h = p.startTime.hour { earliest = min(earliest, h) }
                if let h = p.endTime.hour   { latest   = max(latest,   h + 1) }
            }
        }
        for e in timedEvents {
            earliest = min(earliest, Calendar.current.component(.hour, from: e.startDate))
            latest   = max(latest,   Calendar.current.component(.hour, from: e.endDate) + 1)
        }
        return (max(0, earliest - 1), min(24, latest + 1))
    }

    private var hours: [Int] { Array(timeRange.start ..< timeRange.end) }
    private var totalHeight: CGFloat { CGFloat(hours.count) * hourRowHeight }

    private var allDayEvents: [SchoolEvent] { events.filter {  $0.isAllDay } }
    private var timedEvents:  [SchoolEvent] { events.filter { !$0.isAllDay } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pillRow
                .padding(.horizontal, LS.md)
                .padding(.vertical, LS.sm)

            Divider().overlay(Color.lsTertiary.opacity(0.4))

            // Hour grid + event overlay — no GeometryReader
            ZStack(alignment: .topLeading) {
                hourGrid
                eventLayer
            }
            .frame(height: totalHeight)
        }
    }

    // MARK: - Pill row

    private var pillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LS.xs) {
                pill(scheduleTypeInfo.0, scheduleTypeInfo.1)
                ForEach(allDayEvents) { pill($0.title, categoryColor($0.category)) }
            }
        }
    }

    private func pill(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.lsLabel)
            .foregroundStyle(.white)
            .padding(.horizontal, LS.sm)
            .padding(.vertical, 5)
            .background(color.opacity(0.22))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    private var scheduleTypeInfo: (String, Color) {
        guard let schedule else {
            let wd = Calendar.current.component(.weekday, from: date)
            if events.contains(where: { $0.category == .holiday }) { return ("No School", .lsDestructive) }
            return (wd == 1 || wd == 7) ? ("Weekend", .lsTertiary) : ("No School", .lsDestructive)
        }
        switch schedule.scheduleType {
        case .regular:      return ("Regular Schedule",  .lsBlue)
        case .block:        return ("Block Schedule",     .lsGold)
        case .lateStart:    return ("Late Start",         .lsOrange)
        case .earlyRelease: return ("Early Release",      .lsOrange)
        case .assembly:     return ("Assembly Schedule",  .lsSuccess)
        case .custom:       return ("Modified Schedule",  .lsSecondary)
        case .unknown:      return ("Schedule",           .lsSecondary)
        }
    }

    // MARK: - Hour grid

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    // Full-width rule
                    Rectangle()
                        .fill(Color.lsTertiary.opacity(0.22))
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)

                    // Time label
                    Text(hourLabel(hour))
                        .font(.lsLabel)
                        .foregroundStyle(Color.lsTertiary)
                        .padding(.leading, LS.sm)
                        .offset(y: -9)  // nudge above its line
                }
                .frame(height: hourRowHeight)
            }
        }
    }

    // MARK: - Event layer (overlaid on the grid)

    private var eventLayer: some View {
        ZStack(alignment: .topLeading) {
            // Bell schedule periods
            if let schedule {
                ForEach(Array(overlapGroups(from: schedule).enumerated()), id: \.offset) { _, group in
                    ForEach(Array(group.enumerated()), id: \.offset) { idx, period in
                        if let start = period.startDate(on: schedule.date),
                           let end   = period.endDate(on: schedule.date) {
                            PeriodBlock(
                                period: period,
                                config: periodConfig(for: period),
                                height: blockHeight(from: start, to: end)
                            )
                            .frame(height: max(blockHeight(from: start, to: end), 20))
                            .padding(.leading, columnX(idx: idx, total: group.count))
                            .padding(.trailing, columnTrailing(idx: idx, total: group.count))
                            .offset(y: yOffset(for: start))
                        }
                    }
                }
            }

            // Timed school events
            ForEach(Array(overlapGroupsForEvents(timedEvents).enumerated()), id: \.offset) { _, group in
                ForEach(Array(group.enumerated()), id: \.offset) { idx, event in
                    SchoolEventBlock(
                        event: event,
                        height: blockHeight(from: event.startDate, to: event.endDate)
                    )
                    .frame(height: max(blockHeight(from: event.startDate, to: event.endDate), 20))
                    .padding(.leading, columnX(idx: idx, total: group.count))
                    .padding(.trailing, columnTrailing(idx: idx, total: group.count))
                    .offset(y: yOffset(for: event.startDate))
                }
            }

            // Now line
            if Calendar.current.isDateInToday(date) {
                nowLine
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Now line

    private var nowLine: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { ctx in
            let y = yOffset(for: ctx.date)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.lsDestructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1.5)
                    .padding(.leading, eventInset - 4)
                Circle()
                    .fill(Color.lsDestructive)
                    .frame(width: 8, height: 8)
                    .padding(.leading, eventInset - 8)
            }
            .offset(y: y)
        }
    }

    // MARK: - Layout math

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = cal.component(.hour,   from: date)
        let m = cal.component(.minute, from: date)
        return CGFloat(Double(h) + Double(m) / 60.0 - Double(timeRange.start)) * hourRowHeight
    }

    private func blockHeight(from start: Date, to end: Date) -> CGFloat {
        CGFloat(end.timeIntervalSince(start) / 3600) * hourRowHeight
    }

    // Leading padding for column idx out of total
    private func columnX(idx: Int, total: Int) -> CGFloat {
        let colWidth = columnWidth(total: total)
        return eventInset + CGFloat(idx) * colWidth + 2
    }

    // Trailing padding keeps the block in its column
    private func columnTrailing(idx: Int, total: Int) -> CGFloat {
        let colWidth = columnWidth(total: total)
        let rightEdgePad = CGFloat(total - idx - 1) * colWidth + 2
        return rightEdgePad
    }

    // Approximate column width — good enough without GeometryReader
    // Uses 320 as a baseline screen content width (works for all iPhone sizes)
    private func columnWidth(total: Int) -> CGFloat {
        let availableWidth: CGFloat = 320 - eventInset
        return availableWidth / CGFloat(total)
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0:  return "12a"
        case 12: return "12p"
        default: return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
        }
    }

    private func periodConfig(for period: Period) -> PeriodConfig? {
        let parts = period.name.split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "period", let n = Int(parts[1]) else { return nil }
        return settings.config(for: n)
    }

    private func categoryColor(_ category: EventCategory) -> Color {
        switch category {
        case .bellSchedule: return .lsBlue
        case .athletic:     return .lsOrange
        case .academic:     return .lsGold
        case .liturgy:      return .lsSuccess
        case .holiday:      return .lsDestructive
        case .other:        return .lsSecondary
        }
    }

    // MARK: - Overlap grouping

    private func overlapGroups(from schedule: BellSchedule) -> [[Period]] {
        let sorted = schedule.periods.compactMap { p -> (Period, Date, Date)? in
            guard let s = p.startDate(on: schedule.date), let e = p.endDate(on: schedule.date) else { return nil }
            return (p, s, e)
        }.sorted { $0.1 < $1.1 }
        var result: [[Period]] = []
        var current: [(Period, Date, Date)] = []
        for item in sorted {
            if current.isEmpty || item.1 < current.map(\.2).max()! {
                current.append(item)
            } else {
                result.append(current.map(\.0)); current = [item]
            }
        }
        if !current.isEmpty { result.append(current.map(\.0)) }
        return result
    }

    private func overlapGroupsForEvents(_ events: [SchoolEvent]) -> [[SchoolEvent]] {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var result: [[SchoolEvent]] = []
        var current: [SchoolEvent] = []
        for event in sorted {
            if current.isEmpty || event.startDate < current.map(\.endDate).max()! {
                current.append(event)
            } else {
                result.append(current); current = [event]
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - PeriodBlock

private struct PeriodBlock: View {
    let period: Period
    let config: PeriodConfig?
    let height: CGFloat

    private var color: Color { config.map { Color.paletteColor(for: $0) } ?? .lsSecondary }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                .fill(color.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1))
            Rectangle().fill(color).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(config?.displayName ?? period.name)
                    .font(.lsCaption).fontWeight(.semibold).foregroundStyle(.white).lineLimit(1)
                if height > 36 {
                    Text(timeRangeLabel)
                        .font(.lsLabel).foregroundStyle(Color.lsSecondary).lineLimit(1)
                }
            }
            .padding(.leading, LS.sm).padding(.top, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
    }

    private var timeRangeLabel: String {
        guard let sh = period.startTime.hour, let sm = period.startTime.minute,
              let eh = period.endTime.hour,   let em = period.endTime.minute else { return "" }
        return "\(fmt(sh, sm)) – \(fmt(eh, em))"
    }
    private func fmt(_ h: Int, _ m: Int) -> String {
        let s = h < 12 ? "AM" : "PM"; let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return m == 0 ? "\(h12) \(s)" : "\(h12):\(String(format: "%02d", m)) \(s)"
    }
}

// MARK: - SchoolEventBlock

private struct SchoolEventBlock: View {
    let event:  SchoolEvent
    let height: CGFloat

    private var color: Color {
        switch event.category {
        case .bellSchedule: return .lsBlue;   case .athletic: return .lsOrange
        case .academic:     return .lsGold;   case .liturgy:  return .lsSuccess
        case .holiday:      return .lsDestructive
        case .other:        return .lsSecondary
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1))
            Rectangle().fill(color).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.lsCaption).fontWeight(.semibold).foregroundStyle(.white).lineLimit(1)
                if height > 36 {
                    Text(timeRangeLabel)
                        .font(.lsLabel).foregroundStyle(Color.lsSecondary).lineLimit(1)
                }
            }
            .padding(.leading, LS.sm).padding(.top, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
    }

    private var timeRangeLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.lsBackground.ignoresSafeArea()
        ScrollView {
            EventsDayView(date: Date(), schedule: nil, events: [], settings: UserSettings.shared)
        }
    }
}
