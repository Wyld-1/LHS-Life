//
//  EventDetailSheet.swift
//  LHS Life
//
//  Tap-to-detail sheet for any calendar item — a real SchoolEvent (class
//  events, all-day events, athletics, etc.) or a bell-schedule class period,
//  which isn't backed by a SchoolEvent at all. Restates title, time, and
//  location, then shows the full description when one exists — which is
//  most events per CalendarWiz, but not all, so every section below is
//  conditional and gracefully omitted rather than shown empty.
//

import SwiftUI

enum EventDetailItem: Identifiable {
    case schoolEvent(SchoolEvent)
    case period(Period, config: PeriodConfig?, start: Date, end: Date, scheduleLabel: String)

    var id: String {
        switch self {
        case .schoolEvent(let e):
            return e.id
        case .period(let p, _, let start, _, _):
            return "period-\(p.id)-\(start.timeIntervalSince1970)"
        }
    }

    var title: String {
        switch self {
        case .schoolEvent(let e): return e.title
        case .period(let p, let config, _, _, _): return config?.displayName ?? p.name
        }
    }

    var color: Color {
        switch self {
        case .schoolEvent(let e): return e.category.pillColor
        case .period(_, let config, _, _, _):
            return config.map { Color.paletteColor(for: $0) } ?? Color.lsTertiary
        }
    }

    var location: String? {
        switch self {
        case .schoolEvent(let e): return e.location
        case .period: return nil
        }
    }

    /// Real description for SchoolEvents; for periods, a synthesized note
    /// since there's no per-period description data to restate.
    var description: String? {
        switch self {
        case .schoolEvent(let e): return e.description
        case .period(_, _, _, _, let scheduleLabel): return "Part of today's \(scheduleLabel)."
        }
    }

    // MARK: - Real dates, for saving to the system Calendar (EventDetailSheet's
    // "Save to Calendar" button) — timeRangeText below is display-only and
    // insufficient for that.

    var startDate: Date {
        switch self {
        case .schoolEvent(let e): return e.startDate
        case .period(_, _, let start, _, _): return start
        }
    }

    var endDate: Date {
        switch self {
        case .schoolEvent(let e): return e.endDate
        case .period(_, _, _, let end, _): return end
        }
    }

    var isAllDay: Bool {
        switch self {
        case .schoolEvent(let e): return e.isAllDay
        case .period: return false
        }
    }

    var timeRangeText: String {
        switch self {
        case .schoolEvent(let e):
            if e.isAllDay {
                let cal = Calendar.current
                // iCal all-day DTEND is exclusive (the day AFTER the last day),
                // so the real last day is endDate - 1.
                let lastDay = cal.date(byAdding: .day, value: -1, to: e.endDate) ?? e.endDate
                if cal.isDate(e.startDate, inSameDayAs: lastDay) {
                    return "All day"
                }
                let f = DateFormatter()
                f.dateFormat = "MMM d"
                return "\(f.string(from: e.startDate)) – \(f.string(from: lastDay))"
            } else {
                return "\(ScheduleEngine.timeString(e.startDate)) – \(ScheduleEngine.timeString(e.endDate))"
            }
        case .period(_, _, let start, let end, _):
            return "\(ScheduleEngine.timeString(start)) – \(ScheduleEngine.timeString(end))"
        }
    }

    /// Rough threshold for "this needs the taller detent to be readable."
    /// Character count rather than measured height — the sheet must choose a
    /// detent set before layout runs, so a real measurement isn't available
    /// at this point.
    var hasLongDescription: Bool { (description?.count ?? 0) > 280 }
}

/// Sizes the sheet to its content, capped at 85% of whatever space the sheet
/// actually has.
///
/// `context.maxDetentValue` is the real container height — which is why this
/// exists instead of the `UIScreen.main.bounds.height * 0.85` it replaced.
/// UIScreen is the whole DISPLAY, not the sheet's container, so in iPad Split
/// View the old cap could exceed 100% of the available height and silently
/// stop clamping.
///
/// The measured content height arrives through a static rather than an
/// instance property because `height(in:)` is a static requirement of the
/// protocol. That's ugly but contained: only EventDetailSheet writes it, and
/// only ever from the main actor.
struct ContentFitDetent: CustomPresentationDetent {
    @MainActor static var measuredHeight: CGFloat = 0

    static func height(in context: Context) -> CGFloat? {
        let ceiling = context.maxDetentValue * 0.85
        let measured = MainActor.assumeIsolated { measuredHeight }
        // Floor keeps very short items (a period with a one-line note) from
        // opening as a sliver.
        return min(max(measured, 240), ceiling)
    }
}

struct EventDetailSheet: View {
    let item: EventDetailItem

    /// Measured height of the scrollable content. Drives the custom detent so
    /// the sheet opens exactly tall enough to show the description AND clear
    /// the floating Save button — previously a short two-line description
    /// forced a drag to .large just to read the last line.
    @State private var contentHeight: CGFloat = 0

    /// Space the pinned Save button occupies, plus breathing room. The button
    /// floats over the scroll view rather than sitting in it, so its height
    /// isn't part of contentHeight and has to be added back.
    private let buttonClearance: CGFloat = 96

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: LS.md) {
                    HStack(alignment: .top, spacing: LS.sm) {
                        Capsule()
                            .fill(item.color)
                            .frame(width: 4, height: 30)
                        Text(item.title)
                            .font(.lsTitle)
                            .foregroundStyle(Color.lsPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: LS.sm) {
                        DetailRow(icon: "clock", text: item.timeRangeText, color: item.color)
                        if let location = item.location, !location.isEmpty {
                            DetailRow(icon: "mappin.and.ellipse", text: location, color: item.color)
                                .textSelection(.enabled)
                        }
                    }

                    Rectangle()
                        .fill(Color.lsTertiary.opacity(0.2))
                        .frame(height: 0.5)

                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.lsBody)
                            .foregroundStyle(Color.lsPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        Text("No description provided")
                            .font(.lsBody)
                            .foregroundStyle(Color.lsTertiary)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LS.lg)
                .padding(.bottom, 64)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SheetContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .onPreferenceChange(SheetContentHeightKey.self) { height in
                // Only grow. Once the sheet is open the ScrollView reports its
                // own (clipped) height rather than the content's, so tracking
                // every change would shrink the detent out from under the user.
                if height > contentHeight {
                    contentHeight = height
                    ContentFitDetent.measuredHeight = height + buttonClearance
                }
            }

            SaveToCalendarButton(item: item)
                .padding(.horizontal, LS.xxl)
                // iPhone: bottom safe area lifts the button naturally.
                // iPad: sheets are centered with no bottom safe area, so
                // the button slams the edge without explicit padding.
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? LS.lg : 0)
                .safeAreaPadding(.bottom)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        // Self-sizing against the sheet's real container (see ContentFitDetent).
        // .large stays available by dragging for long descriptions.
        .presentationDetents([.custom(ContentFitDetent.self), .large])
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DetailRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: LS.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.lsHeadline)
                .foregroundStyle(Color.lsSecondary)
        }
    }
}

// MARK: - Save to Calendar Button
// Floating, pinned to the bottom of the sheet regardless of scroll position
// or detent — same placement convention as Apple's own "Delete Event"
// button in the system Calendar app's detail sheet.

private struct SaveToCalendarButton: View {
    let item: EventDetailItem

    private enum SaveState: Equatable { case idle, saving, saved, failed }
    @State private var state: SaveState = .idle

    private var label: String {
        switch state {
        case .idle:    return "Save to Calendar"
        case .saving:  return "Saving…"
        case .saved:   return "Added to Calendar"
        case .failed:  return "Couldn't Save — Try Again"
        }
    }

    private var systemImage: String {
        switch state {
        case .idle, .saving: return "calendar.badge.plus"
        case .saved:          return "checkmark"
        case .failed:          return "exclamationmark.triangle"
        }
    }

    var body: some View {
        Button {
            guard state != .saving && state != .saved else { return }
            Task {
                state = .saving
                let result = await SystemCalendarService.shared.save(item)
                switch result {
                case .success:
                    state = .saved
                    HapticEngine.shared.success()
                case .denied, .failed:
                    state = .failed
                    HapticEngine.shared.error()
                }
            }
        } label: {
            HStack(spacing: LS.sm) {
                if state == .saving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(label)
                    .font(.lsHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LS.sm + 2)
        }
        .buttonStyle(.plain)
        .disabled(state == .saving || state == .saved)
        .modifier(SaveButtonGlassModifier())
    }
}

private struct SaveButtonGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Color.lsBlue)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
    }
}
