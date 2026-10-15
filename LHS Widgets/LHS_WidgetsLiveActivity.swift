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
            let transitions      = transitionDates(from: context.attributes.schedule)
            let schedule         = context.attributes.schedule
            let state            = context.state
            let scheduleTypeName = context.attributes.scheduleTypeName

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
                        HStack(spacing: 6) {
                            if slot?.isPassing == true {
                                Image(systemName: "clock")
                                    .foregroundStyle(Color(hex: slot?.colorHex ?? "#3A6FD8"))
                                    .font(.system(size: 14, weight: .semibold))
                            } else {
                                Image("lhs-lightning")
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundStyle(Color(hex: slot?.colorHex ?? "#3A6FD8"))
                                    .frame(width: 14, height: 14)
                            }
                            Text(slot?.displayName ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white).lineLimit(1)
                        }
                        .padding(.leading, 4)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
                        if let slot, slot.isPreSchool {
                            // Before school: when it starts, not a countdown
                            // that could be hours long.
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text(slot.startTimeString)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }.padding(.trailing, 4)
                        } else if let slot {
                            // One line, level with the period name. The bell's
                            // time sits on the row below, beside "Next:" — a
                            // two-line stack here made this region taller than
                            // the leading one, opening a gap under "Passing"
                            // and pushing the progress bar off the bottom.
                            BellCountdown(from: slot.isPassing ? (slot.passingStartDate ?? slot.startDate) : slot.startDate,
                                          to: slot.isPassing ? slot.startDate : slot.endDate, maxWidth: 120)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.trailing, 4)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.explicit(transitions)) { tl in
                        let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
                        let color = Color(hex: slot?.colorHex ?? "#3A6FD8")
                        VStack(spacing: 6) {
                            if let slot = slot {
                                // Subtitle priority must match LockScreenContent:
                                // passing → "Until", before school → schedule type,
                                // otherwise → next period. This region was missing
                                // the pre-school case, so the Dynamic Island said
                                // "Next: Passing" while the Lock Screen said
                                // "Regular Schedule" for the same instant.
                                if slot.isPassing, let next = slot.nextDisplayName {
                                    HStack {
                                        Text("Next: \(next)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                        Spacer()
                                        Text("until \(slot.startTimeString)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                    }
                                } else if slot.isPreSchool {
                                    HStack {
                                        Text(slot.scheduleTypeName)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                        Spacer()
                                    }
                                } else if let next = slot.nextDisplayName {
                                    HStack {
                                        Text("Next: \(next)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                        Spacer()
                                        Text("until \(slot.endTimeString)")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                    }
                                }
                                if slot.isPreSchool {
                                    // Extra horizontal inset beyond the region's
                                    // own padding. The expanded bottom region sits
                                    // low in the Dynamic Island, where the
                                    // container's corner radius curves inward — a
                                    // full-width bar has its first and last bands
                                    // sliced diagonally by that curve.
                                    //
                                    // Invisible with LiveProgressBar because its
                                    // track ends are faint gray; obvious here,
                                    // where both ends are saturated color.
                                    //
                                    // Lock Screen doesn't need this — its container
                                    // is a plain rounded rect with the bar well
                                    // inside the corner radius.
                                    SchedulePreviewBar(schedule: schedule, height: 6)
                                        .padding(.horizontal, 10)
                                } else if slot.isPassing, let passStart = slot.passingStartDate {
                                    LiveProgressBar(start: passStart, end: slot.startDate, color: color)
                                } else {
                                    LiveProgressBar(start: slot.startDate, end: slot.endDate, color: color)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

            } compactLeading: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
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
                    let slot = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
                    if let slot {
                        // A gray bell and the next bell's time — "🔔 8:55".
                        // No AM/PM: during the school day it's never in doubt,
                        // and the pill stays narrow enough to leave the status
                        // icons alone. Before school, it's the first bell.
                        let bell = (slot.isPreSchool || slot.isPassing) ? slot.startDate : slot.endDate
                        HStack(spacing: 3) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(shortBellTime(bell))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .padding(.trailing, 2)
                    }
                }

            } minimal: {
                TimelineView(.explicit(transitions)) { tl in
                    let slot  = resolveSlot(at: tl.date, schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)
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
            .keylineTint(Color(hex: resolveSlot(at: Date(), schedule: schedule, state: state, scheduleTypeName: scheduleTypeName)?.colorHex ?? "#3A6FD8"))
        }
    }
}

// MARK: - Slot resolver

private struct ActiveSlotInfo {
    let displayName: String
    let colorHex: String
    let startDate: Date
    let endDate: Date
    let endTimeString: String
    let startTimeString: String
    let nextDisplayName: String?
    let nextEndTimeString: String?
    let isPassing: Bool
    let passingStartDate: Date?
    let isPreSchool: Bool
    let scheduleTypeName: String   // shown as subtitle before school
}

/// LaSalle blue — the neutral fallback tint used when no period color
/// applies, and the identity color before school.
private let lsBlueHex = "#3A6FD8"

/// Resolves the active slot from attributes.schedule using state.slotStartMinutes.
/// The worker pushes slotStartMinutes — widget looks it up locally for name/color/dates.
/// Falls back to time-based resolution before first push arrives.
private func resolveSlot(
    at date: Date,
    schedule: [ScheduleActivityAttributes.ScheduledPeriod],
    state: ScheduleActivityAttributes.ContentState,
    scheduleTypeName: String
) -> ActiveSlotInfo? {
    guard !schedule.isEmpty else { return nil }

    let cal = Calendar.current

    // Primary: find slot by slotStartMinutes pushed from server/BGTask
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

    // Time-based resolution
    let activeSlot  = schedule.first(where: { date >= $0.startDate && date < $0.endDate })
    let upcomingSlot = schedule.first(where: { date < $0.startDate })

    // Determine state
    // isPreSchool is purely time-based — don't check pushedSlot here.
    // pushedSlot is set from slotStartMinutes which is always > 0 on start,
    // so requiring pushedSlot == nil would always suppress isPreSchool.
    let isPreSchool = activeSlot == nil && schedule.allSatisfy({ $0.startDate > date })
    let isPassing   = !isPreSchool && activeSlot == nil && upcomingSlot != nil
                      && (schedule.last(where: { $0.endDate <= date }) != nil)

    // The push first. A Live Activity's TimelineView does NOT re-render at
    // each bell on its own — tested: a card cut off from pushes still said
    // "Break" at 9:56, its 9:55 entry never drawn — so the pushed slot is the
    // freshest truth the card has, and the clock only fills in around it.
    let current = pushedSlot ?? activeSlot ?? upcomingSlot
    guard let current else { return nil }

    let idx = schedule.firstIndex(where: { $0.startDate == current.startDate }) ?? 0

    // "Next: X" must always name a CLASS, never a passing period. If the
    // schedule ever models a passing period as its own entry in the array —
    // a name like "Passing" or "Passing Period" sitting between two real
    // classes — a plain schedule[idx + 1] surfaces it verbatim: "Next:
    // Passing period". That's never useful information; the person wants to
    // know the next CLASS, and the passing period is implied by the gap.
    //
    // Walks forward past any such entries to the next actual class.
    var next: ScheduleActivityAttributes.ScheduledPeriod?
    var lookaheadIdx = idx + 1
    while lookaheadIdx < schedule.count {
        let candidate = schedule[lookaheadIdx]
        if !isPassingLikeName(candidate.displayName) {
            next = candidate
            break
        }
        lookaheadIdx += 1
    }

    // For passing: previous slot's end is the passing start
    let prevSlot = idx > 0 ? schedule[idx - 1] : nil
    let passingStartDate: Date? = isPassing ? prevSlot?.endDate : nil

    func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: d)
    }

    // Before school the pill describes the DAY, not a class.
    //
    // `current` resolves to Period 1 here (it's the upcoming slot), so the
    // name and color came out as "Physics" in that period's color — which
    // reads as though Physics is in session at 8:27 AM. The times are still
    // Period 1's, and correctly so: the first bell IS when Physics starts.
    // Only the identity is wrong.
    //
    // "Today" rather than a time-of-day word: what's actually on screen in
    // this state is the whole day — the schedule preview bar underneath, the
    // schedule type as subtitle, and the first bell. The label names that.
    //
    // Neutral LaSalle blue rather than the first period's color, for the same
    // reason: tinting the whole pill orange because first period happens to
    // be orange implies a class that hasn't begun.
    let displayName = isPreSchool ? "Today" : current.displayName
    let colorHex    = isPreSchool ? lsBlueHex : current.colorHex

    return ActiveSlotInfo(
        displayName:      displayName,
        colorHex:         colorHex,
        startDate:        current.startDate,
        endDate:          current.endDate,
        endTimeString:    current.endTimeString,
        startTimeString:  fmt(current.startDate),
        nextDisplayName:  next?.displayName,
        nextEndTimeString: next.map { fmt($0.endDate) },
        isPassing:        isPassing,
        passingStartDate: passingStartDate,
        isPreSchool:      isPreSchool,
        scheduleTypeName: scheduleTypeName
    )
}

/// True for a schedule entry whose NAME identifies it as passing time rather
/// than a class — "Passing", "Passing Period", case-insensitive. Deliberately
/// narrow: only the exact passing-period naming is excluded, so a real class
/// that happens to contain the word (unlikely, but not this function's call
/// to make) is never silently dropped from "Next:".
private func isPassingLikeName(_ name: String) -> Bool {
    let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
    return normalized == "passing" || normalized == "passing period"
}

private func transitionDates(from schedule: [ScheduleActivityAttributes.ScheduledPeriod]) -> [Date] {
    let starts = schedule.map { $0.startDate }
    guard let firstBell = starts.first else { return [] }
    // A TimelineView(.explicit:) schedule has no entry BEFORE its first date,
    // so between the activity starting and the first bell there is nothing for
    // it to render — and it falls forward to the first entry instead. tl.date
    // then equals the first bell, which makes the time-based checks in
    // resolveSlot believe Period 1 is already in session: activeSlot resolves
    // to Period 1, isPreSchool computes false, and the view shows Period 1's
    // END time instead of counting down to its start.
    //
    // Prepending an entry well before the first bell gives the timeline a
    // window that actually covers the pre-school period.
    //
    // The day's last END is added too. Without it, a card started during the
    // last class had no date ahead of it at all — every start was already in
    // the past — and the renderer fell back to the pre-school placeholder
    // above: "Today · school starts 1:30 PM" in the middle of 1:30's class.
    let ends = schedule.last.map { [$0.endDate] } ?? []
    return [firstBell.addingTimeInterval(-12 * 3600)] + starts + ends
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        TimelineView(.explicit(transitionDates(from: attributes.schedule))) { tl in
            if let slot = resolveSlot(at: tl.date, schedule: attributes.schedule, state: state, scheduleTypeName: attributes.scheduleTypeName) {
                LockScreenContent(slot: slot, schedule: attributes.schedule)
            }
        }
    }
}

private struct LockScreenContent: View {
    let slot: ActiveSlotInfo
    let schedule: [ScheduleActivityAttributes.ScheduledPeriod]

    var body: some View {
        let color = Color(hex: slot.colorHex)
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                // Left: lightning/clock + period name + subtitle
                HStack(spacing: 8) {
                    if slot.isPassing {
                        Image(systemName: "clock")
                            .resizable()
                            .foregroundStyle(color)
                            .frame(width: 18, height: 18)
                    } else {
                        Image("lhs-lightning")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(color)
                            .frame(width: 18, height: 18)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if slot.isPassing, let until = slot.nextEndTimeString {
                            Text("Until \(until)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        } else if slot.isPreSchool {
                            Text(slot.scheduleTypeName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        } else if let next = slot.nextDisplayName {
                            Text("Next: \(next)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                // Right: a live countdown to the next bell, with the bell time
                // under it. Before school: when school starts.
                VStack(alignment: .trailing, spacing: 1) {
                    if slot.isPreSchool {
                        Text(slot.startTimeString)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("school starts")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        // During passing time the next bell is the next class
                        // starting; otherwise it's this one ending.
                        let bell = slot.isPassing ? slot.startDate : slot.endDate
                        BellCountdown(from: slot.isPassing ? (slot.passingStartDate ?? slot.startDate) : slot.startDate,
                                      to: bell)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("until \(slot.isPassing ? slot.startTimeString : slot.endTimeString)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }

            if slot.isPreSchool {
                // Whole-day preview instead of a progress bar that would read
                // 0% until the first bell.
                SchedulePreviewBar(schedule: schedule)
            } else if slot.isPassing, let passStart = slot.passingStartDate {
                LiveProgressBar(start: passStart, end: slot.startDate, color: color)
            } else {
                LiveProgressBar(start: slot.startDate, end: slot.endDate, color: color)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(hex: "#0D1220"))
        .activitySystemActionForegroundColor(.white)
    }
}

/// "8:55" — a bell time without AM/PM, for the compact Dynamic Island.
private func shortBellTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm"
    return f.string(from: date)
}

// MARK: - Bell Countdown
//
// "23 minutes" to the next bell, ticking down by itself.
//
// Costs no pushes and no update budget: the system renders this format live,
// the same way it animates LiveProgressBar.
//
// A TIMER over [from, bell), not an offset to the bell. An offset keeps going
// after the bell and, with its sign hidden, counts back UP — a card that went
// stale at 8:55 read "53 minutes until 8:55 AM" at 9:48. A timer stops at the
// end of its range.
//
// The format floors to the whole minute; the app header rounds up ("23 min
// left" with 22:53 to go). Ending the range 59 seconds past the bell makes the
// two agree at every second, and reads "1 minute" in the final seconds rather
// than "0 minutes".

private struct BellCountdown: View {
    let from: Date
    let to: Date
    var maxWidth: CGFloat = 140

    var body: some View {
        Text(.currentDate, format: .timer(
            countingDownIn: min(from, to)..<to.addingTimeInterval(59),
            showsHours: false,
            maxPrecision: .seconds(60)
        ))
        .monospacedDigit()
        // A live-updating Text reserves room for its widest possible value
        // and fills the space it's given, so without this it sits left of
        // its column rather than flush right like the time it replaced.
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: maxWidth, alignment: .trailing)
    }
}

// MARK: - Schedule Preview Bar
//
// Shown before school in place of the progress bar, which would otherwise sit
// at 0% until the first bell. Renders the whole day as proportional colored
// bands: [Period 1][break][Period 3][lunch]… — colors only, no labels.
//
// Reads attributes.schedule, which the app already writes at activity start,
// so this needs no new state and no push. Gaps between slots (passing periods
// the schedule doesn't model as their own entries) render as dim spacers so
// the proportions stay honest.

private struct SchedulePreviewBar: View {
    let schedule: [ScheduleActivityAttributes.ScheduledPeriod]
    var height: CGFloat = 8

    /// Hairline gap between bands. Without it, adjacent similar colors merge
    /// into one indistinguishable block.
    private let spacing: CGFloat = 1

    private struct Band: Identifiable {
        let id: Int
        let fraction: Double
        let color: Color?   // nil = gap
    }

    private var bands: [Band] {
        guard let first = schedule.first, let last = schedule.last else { return [] }
        let total = last.endDate.timeIntervalSince(first.startDate)
        guard total > 0 else { return [] }

        var result: [Band] = []
        var cursor = first.startDate

        for slot in schedule {
            // Gap before this slot (passing time)
            let gap = slot.startDate.timeIntervalSince(cursor)
            if gap > 0 {
                result.append(Band(id: result.count, fraction: gap / total, color: nil))
            }
            let duration = slot.endDate.timeIntervalSince(slot.startDate)
            if duration > 0 {
                result.append(Band(id: result.count, fraction: duration / total,
                                   color: Color(hex: slot.colorHex)))
            }
            cursor = slot.endDate
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let items = bands
            // Subtract the spacing BEFORE distributing width.
            //
            // Previously each band took `geo.size.width * fraction` and the
            // fractions summed to 1.0 — then the HStack added a 1pt gap
            // between each pair on top of that. With a dozen bands the row
            // came out ~11pt wider than the space available, so it overflowed
            // and the Capsule clip sliced the first and last bands off at the
            // ends. Visible before school, but not during class, because the
            // in-class bar is a single ProgressView with no bands at all.
            let gaps = CGFloat(max(0, items.count - 1)) * spacing
            let available = max(0, geo.size.width - gaps)

            HStack(spacing: spacing) {
                ForEach(items) { band in
                    Group {
                        if let color = band.color {
                            color
                        } else {
                            Color.white.opacity(0.10)
                        }
                    }
                    // The last band flexes to absorb sub-pixel rounding from
                    // the fractions, so the row ends flush with the capsule
                    // instead of a hair short or a hair long.
                    .frame(width: band.id == items.count - 1 ? nil : max(1, available * band.fraction))
                    .frame(maxWidth: band.id == items.count - 1 ? .infinity : nil)
                }
            }
            .frame(width: geo.size.width, height: height)
            .clipShape(Capsule())
        }
        .frame(height: height)
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
            scheduleTypeName: "Regular Schedule",
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
