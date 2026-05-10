//
//  WeekStrip.swift
//  LHS Life
//
//  Horizontal paging strip — five Mon–Fri chips per page.
//  Above the scroll view: a tappable week label ("This week", "Next week", …).
//  The label receives an `onLabelTap` closure for the caller to open
//  whatever week/month view comes later.
//

import SwiftUI

// MARK: - WeekStrip

struct WeekStrip: View {

    // MARK: Inputs

    /// The currently selected day (drives the highlighted chip).
    @Binding var selectedDate: Date

    /// Called when the week-label header is tapped.
    var onLabelTap: () -> Void = {}

    // MARK: Private state

    /// Which week page is showing. 0 = this week, 1 = next week, …
    @State private var weekOffset: Int = 0

    private let calendar = Calendar.current

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LS.xs) {
            weekLabel
            chipStrip
        }
    }

    // MARK: - Week label

    private var weekLabel: some View {
        Button(action: {
            HapticEngine.shared.tap()
            onLabelTap()
        }) {
            HStack(spacing: LS.xs) {
                Text(weekLabelText)
                    .font(.lsLabel)
                    .foregroundStyle(Color.lsSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.lsTertiary)
            }
            .padding(.horizontal, LS.md)
        }
        .buttonStyle(.plain)
        .animation(.lsFade, value: weekOffset)
    }

    // MARK: - Chip strip (paging scroll view)

    private var chipStrip: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    // Window: 2 past weeks + this week + 8 future weeks
                    ForEach(-2 ..< 9, id: \.self) { offset in
                        weekPage(for: offset, pageWidth: geo.size.width)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: scrollPositionBinding)
        }
        .frame(height: 64)
    }

    // MARK: - One week page (five chips)

    @ViewBuilder
    private func weekPage(for offset: Int, pageWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(weekDays(offset: offset), id: \.self) { date in
                DayChip(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date)
                ) {
                    withAnimation(.lsSnappy) {
                        selectedDate = date
                    }
                    HapticEngine.shared.tap()
                }
                .frame(width: pageWidth / 5)
            }
        }
        .frame(width: pageWidth)
        .id(offset)
    }

    // MARK: - Scroll position binding

    private var scrollPositionBinding: Binding<Int?> {
        Binding(
            get: { weekOffset },
            set: { newValue in
                if let v = newValue {
                    withAnimation(.lsSnappy) { weekOffset = v }
                }
            }
        )
    }

    // MARK: - Date helpers

    /// Mon–Fri for the given week offset relative to the current week.
    private func weekDays(offset: Int) -> [Date] {
        let today   = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)   // 1 = Sun … 7 = Sat
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let monday = calendar.date(
            byAdding: .day,
            value: daysToMon + offset * 7,
            to: today
        ) else { return [] }
        return (0 ..< 5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var weekLabelText: String {
        switch weekOffset {
        case  0: return "This week"
        case  1: return "Next week"
        case -1: return "Last week"
        default:
            if weekOffset > 0 {
                return weekOffset < 5 ? "\(weekOffset) weeks" : "\((weekOffset * 7) / 30) months"
            } else {
                return "\(-weekOffset) weeks ago"
            }
        }
    }
}

// MARK: - DayChip

private struct DayChip: View {

    let date:       Date
    let isSelected: Bool
    let isToday:    Bool
    var onTap:      () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {

                // Three-letter abbreviated day name
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.lsLabel)
                    .foregroundStyle(labelColor)

                // Date number — circled when today
                ZStack {
                    if isToday {
                        Circle()
                            .fill(circleColor)
                            .frame(width: 30, height: 30)
                    }
                    Text(date.formatted(.dateTime.day()))
                        .font(.lsHeadline)
                        .foregroundStyle(numberColor)
                        .monospacedDigit()
                }
                .frame(width: 30, height: 30)

            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.lsSnappy, value: isSelected)
        .animation(.lsSnappy, value: isToday)
    }

    // MARK: - Colors

    private var circleColor: Color {
        isSelected ? Color.lsBlue : Color.lsSurfaceRaised
    }

    private var labelColor: Color {
        isSelected ? Color.lsBlue : Color.lsTertiary
    }

    private var numberColor: Color {
        if isToday && isSelected { return .white }
        if isToday               { return Color.lsBlue }
        if isSelected            { return .white }
        return Color.lsSecondary
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.lsBackground.ignoresSafeArea()
        VStack(spacing: LS.lg) {
            WeekStrip(
                selectedDate: .constant(Date()),
                onLabelTap: { print("week label tapped") }
            )
            Spacer()
        }
        .padding(.top, LS.lg)
    }
}
