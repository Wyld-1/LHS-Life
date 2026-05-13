//
//  LHS_WidgetsLiveActivity.swift
//  LHS Widgets
//
//  The full day schedule lives in ActivityAttributes, written once at start.
//  TimelineView fires a re-render at each period transition. The widget
//  computes what to display from context.date and attributes.schedule —
//  no ContentState updates are ever needed.
//
//  UserSettings is read from the App Group at render time so custom class
//  names always reflect the student's current configuration.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget

struct LaSalle_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes)
        } dynamicIsland: { context in
            let transitions = transitionDates(from: context.attributes.schedule)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                        HStack(spacing: 6) {
                            Image("lhs-lightning")
                                .resizable().renderingMode(.template)
                                .foregroundStyle(Color(hex: slot?.colorHex ?? "#3A6FD8"))
                                .frame(width: 14, height: 14)
                            Text(slot?.displayName ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white).lineLimit(1)
                        }.padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                        if let endTime = slot?.endTimeString {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(endTime)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }.padding(.trailing, 4)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                        let color = Color(hex: slot?.colorHex ?? "#3A6FD8")
                        VStack(spacing: 6) {
                            if let next = slot?.nextDisplayName {
                                HStack {
                                    Text("Next: \(next)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                    Spacer()
                                }
                            }
                            if let slot = slot {
                                LiveProgressBar(start: slot.startDate, end: slot.endDate, color: color)
                            }
                        }.padding(.horizontal, 4).padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                    Image("lhs-lightning")
                        .resizable().renderingMode(.template)
                        .foregroundStyle(Color(hex: slot?.colorHex ?? "#3A6FD8"))
                        .frame(width: 15, height: 15).padding(.leading, 2)
                }
            } compactTrailing: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                    if let endTime = slot?.endTimeString {
                        Text(endTime)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white).padding(.trailing, 2)
                    }
                }
            } minimal: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot = resolveSlot(at: tl.date, schedule: context.attributes.schedule)
                    let color = Color(hex: slot?.colorHex ?? "#3A6FD8")
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                        if let slot = slot {
                            LiveProgressArc(start: slot.startDate, end: slot.endDate, color: color)
                        }
                        Image("lhs-lightning")
                            .resizable().renderingMode(.template)
                            .foregroundStyle(color).frame(width: 8, height: 8)
                    }.padding(2)
                }
            }
            .keylineTint(Color(hex: resolveSlot(at: Date(), schedule: context.attributes.schedule)?.colorHex ?? "#3A6FD8"))
        }
    }
}

private struct ActiveSlotInfo {
    let displayName: String
    let colorHex: String
    let startDate: Date
    let endDate: Date
    let endTimeString: String
    let nextDisplayName: String?
}

private func resolveSlot(
    at date: Date,
    schedule: [ScheduleActivityAttributes.ScheduledPeriod]
) -> ActiveSlotInfo? {
    guard !schedule.isEmpty else { return nil }

    let settings = UserSettings.shared

    // Find current slot
    guard let current = schedule.first(where: { date >= $0.startDate && date < $0.endDate })
            ?? schedule.first(where: { date < $0.startDate })  // before school
    else { return nil }

    // Resolve display name from UserSettings if we have a period number
    let displayName: String
    if let num = current.periodNumber,
       let config = settings.config(for: num) {
        displayName = config.displayName
    } else {
        displayName = current.fallbackName
    }

    // Next slot
    let nextSlot = schedule.first(where: { $0.startDate >= current.endDate })
    let nextDisplayName: String?
    if let next = nextSlot {
        if let num = next.periodNumber,
           let config = settings.config(for: num) {
            nextDisplayName = config.displayName
        } else {
            nextDisplayName = next.fallbackName
        }
    } else {
        nextDisplayName = nil
    }

    return ActiveSlotInfo(
        displayName:     displayName,
        colorHex:        current.colorHex,
        startDate:       current.startDate,
        endDate:         current.endDate,
        endTimeString:   current.endTimeString,
        nextDisplayName: nextDisplayName
    )
}

// MARK: - Transition dates for TimelineView
// One entry per period start so the widget re-renders at each bell.

private func transitionDates(
    from schedule: [ScheduleActivityAttributes.ScheduledPeriod]
) -> [Date] {
    schedule.map { $0.startDate }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes

    var body: some View {
        TimelineView(.explicit(transitionDates(from: attributes.schedule))) { context in
            if let slot = resolveSlot(at: context.date, schedule: attributes.schedule) {
                LockScreenContent(slot: slot)
            } else {
                Text("No schedule")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(16)
            }
        }
    }
}

private struct LockScreenContent: View {
    let slot: ActiveSlotInfo

    var body: some View {
        let color = Color(hex: slot.colorHex)
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(color)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let next = slot.nextDisplayName {
                            Text("Next: \(next)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(slot.endTimeString)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("next bell")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            // Progress bar — live every frame
            LiveProgressBar(start: slot.startDate, end: slot.endDate, color: color)
        }
        .padding(16)
        .activityBackgroundTint(Color(hex: "#0D1220"))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Live Progress Bar
// TimelineView(.animation) redraws every frame. Progress computed from Date().

private struct LiveProgressBar: View {
    let start: Date
    let end: Date
    let color: Color

    var body: some View {
        TimelineView(.animation) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 6)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private var progress: Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / total))
    }
}

// MARK: - Live Progress Arc (minimal)

private struct LiveProgressArc: View {
    let start: Date
    let end: Date
    let color: Color

    private var progress: Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / total))
    }

    var body: some View {
        TimelineView(.animation) { _ in
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

extension ScheduleActivityAttributes {
    fileprivate static var preview: ScheduleActivityAttributes {
        let now = Date()
        return ScheduleActivityAttributes(
            schoolName: "LaSalle",
            schedule: [
                .init(periodNumber: 1, fallbackName: "Period 1", colorHex: "#FF6B6B",
                      startDate: now.addingTimeInterval(-1200),
                      endDate: now.addingTimeInterval(1800),
                      endTimeString: "8:50 AM"),
                .init(periodNumber: 2, fallbackName: "Period 2", colorHex: "#3A6FD8",
                      startDate: now.addingTimeInterval(1800),
                      endDate: now.addingTimeInterval(5400),
                      endTimeString: "9:45 AM"),
                .init(periodNumber: nil, fallbackName: "Break", colorHex: "#94A3B8",
                      startDate: now.addingTimeInterval(5400),
                      endDate: now.addingTimeInterval(6000),
                      endTimeString: "10:00 AM"),
            ]
        )
    }
}

#Preview("In Class", as: .content, using: ScheduleActivityAttributes.preview) {
    LaSalle_WidgetsLiveActivity()
} contentStates: {
    ScheduleActivityAttributes.ContentState()
}
