//
//  ScheduleHeader.swift
//  LaSalle Schedule
//

import SwiftUI

struct ScheduleHeader: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @Binding var showSettings: Bool

    @State private var now: Date = Date()
    @State private var timer: Timer? = nil

    private var state: ScheduleEngine.ScheduleState {
        store.todayState(at: now)
    }

    // Home events only — at LaSalle or Marquette, next 2 days, non-bell-schedule
    private var upcomingHighlight: SchoolEvent? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
              let dayAfter  = cal.date(byAdding: .day, value: 2, to: now) else { return nil }

        let keys = [
            DateFormatter.isoDay.string(from: tomorrow),
            DateFormatter.isoDay.string(from: dayAfter)
        ]

        return keys
            .flatMap { store.events(on: $0) }
            .first { event in
                guard event.category != .bellSchedule else { return false }
                return isHomeEvent(event)
            }
    }

    /// Home events are at LaSalle or Marquette. Away events are excluded.
    private func isHomeEvent(_ event: SchoolEvent) -> Bool {
        let loc = (event.location ?? "").lowercased()
        let title = event.title.lowercased()
        let combined = loc + " " + title

        // If there's no location, include non-athletic events (assemblies, dress days, etc.)
        if loc.isEmpty { return event.category != .athletic }

        // Athletic events: only home games
        let homeVenues = ["lasalle", "la salle", "marquette", "lhs", "home"]
        return homeVenues.contains { combined.contains($0) }
    }

    var body: some View {
        HStack(spacing: LS.sm) {
            pillContent.frame(maxWidth: .infinity)
            gearButton
        }
    }

    // MARK: - Pill

    private var pillContent: some View {
        ZStack(alignment: .leading) {
            // Background
            if #available(iOS 26.0, *) {
                Capsule()
                    .glassEffect()
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            }

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
                        .foregroundStyle(Color.lsPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let sub = secondaryText {
                        Text(sub)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, LS.md)
            .padding(.vertical, LS.sm)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
    }

    // MARK: - Gear Button

    @ViewBuilder
    private var gearButton: some View {
        // MARK: Glass settings button
        if #available(iOS 26.0, *) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Color.lsSecondary)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        } else {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Color.lsSecondary)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
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
        case .afterSchool:  return weekendText
        case .noSchedule:   return weekendText
        case .pathwaysDay:  return "Intership Day"
        case .holiday:      return "No school today"
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
        case 6:  return "Happy Friday 🎉"
        case 7, 1: return "Enjoy the weekend"
        default: return "No school today"
        }
    }

    private func upcomingEventText(_ event: SchoolEvent) -> String {
        let isTomorrow = Calendar.current.isDateInTomorrow(event.startDate)
        let dayName = isTomorrow ? "tomorrow" : DateFormatter.shortWeekday.string(from: event.startDate)
        if event.isAllDay {
            return "\(event.title): \(dayName)"
        } else {
            return "\(event.title): \(dayName) @ \(ScheduleEngine.timeString(event.startDate))"
        }
    }

    private func progressColor(slot: ScheduleEngine.ActiveSlot) -> Color {
        guard let config = slot.config else { return Color.lsBlue }
        return Color.paletteColor(for: config)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in now = Date() }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
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
