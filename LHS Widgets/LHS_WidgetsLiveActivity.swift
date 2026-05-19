//
//  LHS_WidgetsLiveActivity.swift
//  LHS Widgets
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget

struct LaSalle_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            let transitions = transitionDates(from: context.attributes.schedule)
            let schedule    = context.attributes.schedule
            let state       = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: schedule, state: state)
                        HStack(spacing: 6) {
                            Image("lhs-lightning")
                                .resizable()
                                .renderingMode(.template)
                                .foregroundStyle(Color(hex: slot?.colorHex ?? "#3A6FD8"))
                                .frame(width: 14, height: 14)
                            Text(slot?.displayName ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white).lineLimit(1)
                        }
                        .padding(.leading, 4)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: schedule, state: state)
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
                        let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state)
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
                        }
                        .padding(.horizontal, 4)
                    }
                }

            } compactLeading: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state)
                    let color = Color(hex: slot?.colorHex ?? "#3A6FD8")
                    ZStack {
                        if let slot = slot {
                            LiveProgressArc(start: slot.startDate, end: slot.endDate, color: color)
                        }
                        Image("lhs-lightning")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(color).frame(width: 8, height: 8)
                    }
                    .padding(2)
                }

            } compactTrailing: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot = resolveSlot(at: tl.date, schedule: schedule, state: state)
                    if let endTime = slot?.endTimeString {
                        Text(endTime)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white).padding(.trailing, 2)
                    }
                }

            } minimal: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state)
                    let color = Color(hex: slot?.colorHex ?? "#3A6FD8")
                    ZStack {
                        if let slot = slot {
                            LiveProgressArc(start: slot.startDate, end: slot.endDate, color: color)
                        }
                        Image("lhs-lightning")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(color).frame(width: 8, height: 8)
                    }
                    .padding(2)
                }
            }
            .keylineTint(Color(hex: resolveSlot(at: Date(), schedule: schedule, state: state)?.colorHex ?? "#3A6FD8"))
        }
    }
}

// MARK: - Slot resolver

private struct ActiveSlotInfo {
    let displayName: String
    let colorHex: String
    let startDate: Date
    let endDate: Date
    let endTimeString: String   // formatted bell time e.g. "10:50 AM" — shown on trailing
    let nextDisplayName: String?
}

/// Resolves the active slot from attributes.schedule using state.slotStartMinutes.
/// The worker pushes slotStartMinutes — widget looks it up locally for name/color/dates.
/// Falls back to time-based resolution before first push arrives.
private func resolveSlot(
    at date: Date,
    schedule: [ScheduleActivityAttributes.ScheduledPeriod],
    state: ScheduleActivityAttributes.ContentState
) -> ActiveSlotInfo? {
    guard !schedule.isEmpty else { return nil }

    // Primary: find slot by slotStartMinutes pushed from server/BGTask
    let cal = Calendar.current
    let pushedSlot: ScheduleActivityAttributes.ScheduledPeriod?
    if state.slotStartMinutes > 0 {
        pushedSlot = schedule.first {
            let h = cal.component(.hour,   from: $0.startDate)
            let m = cal.component(.minute, from: $0.startDate)
            return h * 60 + m == state.slotStartMinutes
        }
    } else {
        pushedSlot = nil
    }

    // Fallback: find by current time
    let current = pushedSlot
                ?? schedule.first(where: { date >= $0.startDate && date < $0.endDate })
                ?? schedule.first(where: { date < $0.startDate })

    guard let current else { return nil }

    let idx  = schedule.firstIndex(where: { $0.startDate == current.startDate }) ?? 0
    let next = idx + 1 < schedule.count ? schedule[idx + 1] : nil

    return ActiveSlotInfo(
        displayName:     current.displayName,
        colorHex:        current.colorHex,
        startDate:       current.startDate,
        endDate:         current.endDate,
        endTimeString:   current.endTimeString,
        nextDisplayName: next?.displayName
    )
}

private func transitionDates(from schedule: [ScheduleActivityAttributes.ScheduledPeriod]) -> [Date] {
    schedule.map { $0.startDate }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        TimelineView(.explicit(transitionDates(from: attributes.schedule))) { tl in
            if let slot = resolveSlot(at: tl.date, schedule: attributes.schedule, state: state) {
                LockScreenContent(slot: slot)
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
                // Left: lightning + current period + next period
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
                // Right: next bell time
                VStack(alignment: .trailing, spacing: 1) {
                    Text(slot.endTimeString)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("next bell")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            LiveProgressBar(start: slot.startDate, end: slot.endDate, color: color)
        }
        .padding(16)
        .activityBackgroundTint(Color(hex: "#0D1220"))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Live Progress Bar
// ProgressView(timerInterval:) is interpolated natively by iOS —
// no render budget consumed, works all day locked.

private struct LiveProgressBar: View {
    let start: Date
    let end: Date
    let color: Color

    var body: some View {
        ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(color)
        .scaleEffect(x: 1, y: 1.5, anchor: .center)
    }
}

// MARK: - Live Progress Arc (minimal)

private struct LiveProgressArc: View {
    let start: Date
    let end: Date
    let color: Color

    var body: some View {
        ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(color)
        .frame(width: 18, height: 18)
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
                .init(periodNumber: 1, displayName: "English", colorHex: "#FF6B6B",
                      startDate: now.addingTimeInterval(-1200),
                      endDate: now.addingTimeInterval(1800), endTimeString: "8:50 AM"),
                .init(periodNumber: 2, displayName: "Chemistry", colorHex: "#3A6FD8",
                      startDate: now.addingTimeInterval(1800),
                      endDate: now.addingTimeInterval(5400), endTimeString: "9:45 AM"),
                .init(periodNumber: nil, displayName: "Break", colorHex: "#94A3B8",
                      startDate: now.addingTimeInterval(5400),
                      endDate: now.addingTimeInterval(6000), endTimeString: "10:00 AM"),
            ]
        )
    }
}

#Preview("In Class", as: .content, using: ScheduleActivityAttributes.preview) {
    LaSalle_WidgetsLiveActivity()
} contentStates: {
    ScheduleActivityAttributes.ContentState()
}
