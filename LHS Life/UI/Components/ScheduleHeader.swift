//
//  ScheduleHeader.swift
//  LHS Life
//
//  Two independent components:
//
//  ScheduleHeaderPill — the pill with text and progress fill. No settings button.
//                       Used by both iPhone (top) and iPad (bottom accessory).
//
//  SettingsButton     — standalone settings button, always pinned top-right.
//
//  The 1-second timer lives in ScheduleHeaderPill since it owns the live state.
//

import SwiftUI

// MARK: - Settings Button (always top-right, platform-agnostic)

struct SettingsButton: View {
    @Binding var showSettings: Bool

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(Color.lsSecondary)
                .font(.system(size: 42, weight: .semibold))
                .shadow(color: .black.opacity(0.5), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Header Pill

struct ScheduleHeaderPill: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings

    /// Called when the pill is tapped — used to navigate to Events tab on iPhone.
    var onPillTap: (() -> Void)? = nil

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var state: ScheduleEngine.ScheduleState {
        store.todayState(at: now)
    }

    // MARK: - Upcoming highlight

    private var upcomingHighlight: SchoolEvent? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)

        let lookAheadKeys: [String]
        switch weekday {
        case 7:
            lookAheadKeys = [DateFormatter.isoDay.string(from: now)]
        case 1:
            let monday = cal.date(byAdding: .day, value: 1, to: now) ?? now
            lookAheadKeys = [
                DateFormatter.isoDay.string(from: now),
                DateFormatter.isoDay.string(from: monday)
            ]
        default:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            lookAheadKeys = [DateFormatter.isoDay.string(from: tomorrow)]
        }

        return lookAheadKeys
            .flatMap { store.events(on: $0) }
            .first { event in
                guard event.category != .bellSchedule else { return false }
                return isHomeEvent(event)
            }
    }

    private func isHomeEvent(_ event: SchoolEvent) -> Bool {
        guard event.category == .athletic else { return true }
        let loc = (event.location ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard !loc.isEmpty else { return false }
        let homeVenues = ["lasalle", "la salle", "marquette", "lhs", "home"]
        return homeVenues.contains { loc.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            // Progress fill
            if state.dayState == .inSession, let slot = state.currentSlot {
                GeometryReader { geo in
                    Capsule()
                        .fill(progressColor(slot: slot))
                        .opacity(0.18)
                        .frame(width: geo.size.width * slot.progress)
                        .animation(.lsFade, value: slot.progress)
                }
            }

            // Text
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
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, LS.md)
            .padding(.vertical, LS.sm)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().glassEffect(.regular.interactive())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            guard onPillTap != nil else { return }
            HapticEngine.shared.tap()
            onPillTap?()
        }
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Text Logic

    private var primaryText: String {
        switch state.dayState {
        case .inSession:
            guard let slot = state.currentSlot else { return "" }
            let mins = Int(ceil(slot.timeRemaining / 60))
            return "\(mins) min left in \(slot.displayName)"
        case .betweenPeriods:
            guard let next = state.nextSlot else { return "" }
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            return "\(next.displayName) in \(mins) min"
        case .beforeSchool:
            guard let next = state.nextSlot else { return weekendText }
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            return mins > 60 ? "School at \(ScheduleEngine.timeString(next.startDate))" : "School in \(mins) min"
        case .afterSchool:   return weekendText
        case .noSchedule:    return weekendText
        case .pathwaysDay:   return "Internship Day"
        case .holiday:       return "No school today"
        }
    }

    private var secondaryText: String? {
        switch state.dayState {
        case .inSession:
            guard let next = state.nextSlot else { return nil }
            return "Next: \(next.displayName) at \(ScheduleEngine.timeString(next.startDate))"
        case .betweenPeriods:
            guard let next = state.nextSlot else { return nil }
            return "Until \(ScheduleEngine.timeString(next.endDate))"
        case .afterSchool, .noSchedule, .beforeSchool:
            return upcomingHighlight.map { upcomingEventText($0) }
        default:
            return nil
        }
    }

    private var weekendText: String {
        switch Calendar.current.component(.weekday, from: now) {
        case 6:    return "Happy Friday 🎉"
        case 7, 1: return "Enjoy the weekend!"
        default:   return "No school today"
        }
    }

    private func upcomingEventText(_ event: SchoolEvent) -> String {
        let isTomorrow = Calendar.current.isDateInTomorrow(event.startDate)
        let dayName = isTomorrow ? "tomorrow" : DateFormatter.shortWeekday.string(from: event.startDate)
        return event.isAllDay
            ? "\(event.title): \(dayName)"
            : "\(event.title): \(dayName) @ \(ScheduleEngine.timeString(event.startDate))"
    }

    private func progressColor(slot: ScheduleEngine.ActiveSlot) -> Color {
        guard let config = slot.config else { return Color.lsBlue }
        return Color.paletteColor(for: config)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                self.now = Date()
                LiveActivityService.shared.update(
                    state: self.store.todayState(at: self.now),
                    settings: self.settings
                )
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
}

// MARK: - Convenience: iPhone header (pill + settings button together)
// Used only on iPhone where they appear as one unit at the top.

struct ScheduleHeader: View {
    @Binding var showSettings: Bool
    var onPillTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: LS.sm) {
            ScheduleHeaderPill(onPillTap: onPillTap)
                .frame(maxWidth: .infinity)
            SettingsButton(showSettings: $showSettings)
        }
    }
}

private extension DateFormatter {
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}

#Preview {
    ZStack(alignment: .top) {
        Color.lsBackground.ignoresSafeArea()
        ScheduleHeader(showSettings: .constant(false))
            .environment(CalendarStore())
            .environment(UserSettings.shared)
            .padding(.horizontal, LS.md)
            .padding(.top, LS.sm)
            .safeAreaPadding(.top)
    }
}
