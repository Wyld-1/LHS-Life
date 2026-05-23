//
//  SettingsSheetView.swift
//  LHS Life
//

import SwiftUI
#if DEBUG
import UserNotifications
import ActivityKit
#endif

struct SettingsSheetView: View {
    @Bindable var settings: UserSettings
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingPeriodID: Int? = nil
    @FocusState private var gradYearFocused: Bool
    @State private var gradYearInput = ""
    @State private var isEditingGradYear = false
    @State private var apModeEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.lsTitle)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                Button("Done") {
                    commitGradYear()
                    settings.apModeEnabledToday = apModeEnabled
                    settings.save()
                    HapticEngine.shared.success()
                    dismiss()
                }
                .font(.lsHeadline)
                .foregroundStyle(Color.lsBlue)
            }
            .padding(.horizontal, LS.md)
            .padding(.top, LS.lg)
            .padding(.bottom, LS.md)

            Divider().background(Color.lsTertiary.opacity(0.3))

            ScrollView {
                LazyVStack(spacing: LS.lg, pinnedViews: []) {
                    apExamBannerSection
                    gradYearSection
                    periodsSection
                    notificationsSection   // includes Live Activity
                    asbSection             // moved to bottom — power user feature
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, LS.md)
                .padding(.top, LS.md)
                .padding(.bottom, LS.xxl)
            }
        }
        .background(Color.lsSurface)
        .onAppear { apModeEnabled = settings.apModeEnabledToday }
        .onDisappear { settings.save() }
    }

    // MARK: - AP Exam Banner (top of settings)

    private var apExamState: APExamService.APExamState {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        return APExamService.examState(
            for: dayKey,
            events: store.events(on: dayKey),
            settings: settings
        )
    }

    @ViewBuilder
    private var apExamBannerSection: some View {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let examState = APExamService.examState(
            for: dayKey,
            events: store.events(on: dayKey),
            settings: settings
        )
        switch examState {
        case .mine(let name, _, _, let config):
            let color = config.map { Color.paletteColor(for: $0) } ?? Color.lsBlue
            APExamBanner(
                examName: name,
                isSilenced: apModeEnabled,
                accentColor: color,
                onToggle: { HapticEngine.shared.tap(); apModeEnabled.toggle() }
            )
        case .someoneElses(let name, _):
            APExamBanner(
                examName: name,
                isSilenced: apModeEnabled,
                accentColor: Color.lsBlue,
                onToggle: { HapticEngine.shared.tap(); apModeEnabled.toggle() }
            )
        case .none:
            EmptyView()
        }
    }

    // MARK: - Grad Year

    private var gradYearSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("My Info")
            HStack {
                Text("Graduation Year")
                    .font(.lsHeadline)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                ZStack(alignment: .trailing) {
                    HStack(spacing: LS.sm) {
                        TextField("", text: $gradYearInput)
                            .font(.lsTime)
                            .foregroundStyle(Color.lsBlue)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($gradYearFocused)
                            .onSubmit { commitGradYear() }
                        Button("Save") { commitGradYear() }
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsBlue)
                    }
                    .opacity(isEditingGradYear ? 1 : 0)
                    .allowsHitTesting(isEditingGradYear)

                    Button {
                        gradYearInput = String(settings.graduationYear)
                        isEditingGradYear = true
                        gradYearFocused = true
                        HapticEngine.shared.tap()
                    } label: {
                        Text(String(settings.graduationYear))
                            .font(.lsTime)
                            .foregroundStyle(Color.lsBlue)
                            .padding(.horizontal, LS.sm)
                            .padding(.vertical, LS.xs)
                            .background(Color.lsBlue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(isEditingGradYear ? 0 : 1)
                    .allowsHitTesting(!isEditingGradYear)
                }
            }
            .padding(LS.md)
            .lsCard()
        }
    }

    private func commitGradYear() {
        if let year = Int(gradYearInput), year > 2020, year < 2040 {
            settings.graduationYear = year
        }
        isEditingGradYear = false
        gradYearFocused = false
    }

    // MARK: - Periods

    private var periodsSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("My Classes")
            VStack(spacing: 0) {
                ForEach($settings.periodConfigs) { $config in
                    PeriodRow(
                        config: $config,
                        isEditing: editingPeriodID == config.id,
                        onTapName: {
                            HapticEngine.shared.tick()
                            withAnimation(.lsSnappy) {
                                editingPeriodID = editingPeriodID == config.id ? nil : config.id
                            }
                        }
                    )
                    if config.id < 8 {
                        Divider()
                            .background(Color.lsTertiary.opacity(0.3))
                            .padding(.leading, 56)
                    }
                }
            }
            .lsCard()
        }
    }

    // MARK: - Notifications + Live Activity

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("Alerts")
            VStack(spacing: 0) {
                Toggle(isOn: $settings.professionalDressNotificationsEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Professional Dress")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Notify the evening before dress days")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: settings.professionalDressNotificationsEnabled) { _, _ in
                    HapticEngine.shared.tap()
                }

                Divider().background(Color.lsTertiary.opacity(0.3))

                // Live Activity mode — Menu with three options
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Activities")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text(settings.liveActivityMode.description)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(LiveActivityMode.allCases, id: \.rawValue) { mode in
                            Button {
                                settings.liveActivityMode = mode
                                HapticEngine.shared.tick()
                            } label: {
                                if settings.liveActivityMode == mode {
                                    Label(mode.label, systemImage: "checkmark")
                                } else {
                                    Text(mode.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: LS.xs) {
                            Text(settings.liveActivityMode.label)
                                .font(.lsBody)
                                .foregroundStyle(Color.lsBlue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.lsBlue)
                        }
                        .padding(.horizontal, LS.sm)
                        .padding(.vertical, LS.xs)
                        .background(Color.lsBlue.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .tint(Color.lsPrimary)
                }
                .padding(LS.md)
            }
            .lsCard()
        }
    }

    // MARK: - ASB (moved to bottom)

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]

    private var asbSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("Student Leadership")
            VStack(spacing: 0) {
                Toggle(isOn: $settings.isASBMember) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ASB Member")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Enables student leadership reminders")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: settings.isASBMember) { _, _ in HapticEngine.shared.tap() }

                if settings.isASBMember {
                    Divider()
                        .background(Color.lsTertiary.opacity(0.3))

                    VStack(alignment: .leading, spacing: LS.md) {
                        Text("My working days:")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .padding(.horizontal, LS.md)
                            .padding(.top, LS.md)

                        // Day buttons — tap to cycle through three states
                        HStack(spacing: LS.sm) {
                            ForEach(0..<5, id: \.self) { i in
                                let mode = settings.asbWorkDays[i]
                                Button {
                                    HapticEngine.shared.tick()
                                    settings.asbWorkDays[i] = mode.next
                                } label: {
                                    Text(Self.weekdayNames[i])
                                        .font(.lsCaption)
                                        .foregroundStyle(mode == .off ? Color.lsSecondary : .white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, LS.sm)
                                        .background(
                                            mode == .off
                                                ? Color.lsSurfaceRaised
                                                : Color(hex: mode.color)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .animation(.lsSnappy, value: mode)
                            }
                        }
                        .padding(.horizontal, LS.md)

                        // Color key
                        VStack(alignment: .leading, spacing: LS.xs) {
                            ForEach(ASBDayMode.allCases.filter { $0 != .off }, id: \.rawValue) { m in
                                HStack(spacing: LS.xs) {
                                    Circle()
                                        .fill(Color(hex: m.color))
                                        .frame(width: 8, height: 8)
                                    Text(m.label)
                                        .font(.lsCaption)
                                        .foregroundStyle(Color.lsSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, LS.md)
                        .padding(.bottom, LS.md)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .lsCard()
            .animation(.lsSnappy, value: settings.isASBMember)
        }
    }

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("Debug")
            VStack(spacing: 0) {
                Button {
                    HapticEngine.shared.tap()
                    Task {
                        let content = UNMutableNotificationContent()
                        content.title = "Morning Announcements"
                        content.body  = "> This is a DEBUG test"
                        content.sound = .default
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
                        try? await UNUserNotificationCenter.current().add(
                            UNNotificationRequest(identifier: "debug-announcement", content: content, trigger: trigger)
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.circle.fill")
                            .foregroundStyle(Color.lsBlue)
                        Text("Send Announcement Notification")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsBlue)
                        Spacer()
                        Text("3s")
                            .font(.lsLabel)
                            .foregroundStyle(Color.lsTertiary)
                    }
                    .padding(LS.md)
                }
                Divider().background(Color.lsTertiary.opacity(0.3))
                
                Button {
                    HapticEngine.shared.tap()
                    let now = Date()
                    let fmt = DateFormatter()
                    fmt.dateFormat = "h:mm a"
                    let p1End   = now.addingTimeInterval(120)  // +2 min
                    let passEnd = now.addingTimeInterval(150)  // +2 min 30 s
                    let p2End   = now.addingTimeInterval(270)  // +4 min 30 s
                    let periods: [ScheduleActivityAttributes.ScheduledPeriod] = [
                        .init(periodNumber: 1, displayName: "English",
                              colorHex: "#FF6B6B",
                              startDate: now.addingTimeInterval(-5),
                              endDate: p1End,
                              endTimeString: fmt.string(from: p1End)),
                        .init(periodNumber: nil, displayName: "Passing",
                              colorHex: "#94A3B8",
                              startDate: p1End,
                              endDate: passEnd,
                              endTimeString: fmt.string(from: passEnd)),
                        .init(periodNumber: 2, displayName: "Chemistry",
                              colorHex: "#F5B800",
                              startDate: passEnd,
                              endDate: p2End,
                              endTimeString: fmt.string(from: p2End)),
                    ]
                    let cal = Calendar.current
                    let h = cal.component(.hour,   from: periods[0].startDate)
                    let m = cal.component(.minute, from: periods[0].startDate)
                    let state = ScheduleActivityAttributes.ContentState(
                        slotStartMinutes: h * 60 + m,
                        isEnded: false
                    )
                    CachedSchedule.save(periods)
                    do {
                        let activity = try Activity.request(
                            attributes: ScheduleActivityAttributes(
                                schoolName: "LaSalle",
                                scheduleTypeName: "Regular Schedule",
                                schedule: periods
                            ),
                            content: .init(state: state, staleDate: now.addingTimeInterval(6000)),
                            pushType: .token
                        )
                        PushTokenService.observeTokenUpdates(for: activity, periods: periods)
                        BellTransitionService.scheduleTransitions(for: periods.filter { $0.startDate > now })
                        print("[Debug] Dummy Live Activity started")
                    } catch {
                        print("[Debug] Dummy start failed: \(error)")
                    }
                } label: {
                    HStack {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(Color.lsOrange)
                        Text("Force Start Live Activity")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsOrange)
                        Spacer()
                        Text("Dummy")
                            .font(.lsLabel)
                            .foregroundStyle(Color.lsTertiary)
                    }
                    .padding(LS.md)
                }

                Divider().background(Color.lsTertiary.opacity(0.3))

                Button {
                    HapticEngine.shared.tap()
                    let now      = Date()
                    let dayKey   = DateFormatter.isoDay.string(from: now)
                    let schedule = store.bellSchedules[dayKey]
                    LiveActivityService.shared.startIfNeeded(
                        schedule: schedule,
                        settings: settings
                    )
                    print("[Debug] Real start attempted")
                } label: {
                    HStack {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(Color.lsGold)
                        Text("Force Start Live Activity")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsGold)
                        Spacer()
                        Text("Real")
                            .font(.lsLabel)
                            .foregroundStyle(Color.lsTertiary)
                    }
                    .padding(LS.md)
                }

                Divider().background(Color.lsTertiary.opacity(0.3))

                Button(role: .destructive) {
                    HapticEngine.shared.tap()
                    Task {
                        for activity in Activity<ScheduleActivityAttributes>.activities {
                            await activity.end(nil, dismissalPolicy: .immediate)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.lsDestructive)
                        Text("End Live Activity")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsDestructive)
                        Spacer()
                    }
                    .padding(LS.md)
                }
            }
            .lsCard()
        }
    }
    #endif

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.lsLabel)
            .foregroundStyle(Color.lsSecondary)
            .tracking(1)
            .padding(.leading, LS.xs)
    }
}

// MARK: - Period Row

private struct PeriodRow: View {
    @Binding var config: PeriodConfig
    let isEditing: Bool
    let onTapName: () -> Void

    @State private var nameInput = ""
    @State private var showColorPicker = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: LS.md) {
            Text(String(config.id))
                .font(.lsLabel)
                .foregroundStyle(Color.lsTertiary)
                .frame(width: 12, alignment: .center)

            Button {
                showColorPicker = true
                HapticEngine.shared.tick()
            } label: {
                Circle()
                    .fill(Color.paletteColor(for: config))
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .opacity(config.isEnabled ? 1.0 : 0.4)
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                ColorPickerPopup(selectedIndex: config.colorIndex) { index in
                    config = PeriodConfig(
                        id: config.id,
                        customName: config.customName,
                        colorIndex: index,
                        isEnabled: config.isEnabled
                    )
                    showColorPicker = false
                    HapticEngine.shared.tick()
                }
                .presentationCompactAdaptation(.popover)
            }

            if isEditing {
                TextField("Period \(config.id)", text: $nameInput)
                    .font(.lsBody)
                    .foregroundStyle(Color.lsPrimary)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitName() }
                    .onAppear {
                        nameInput = config.customName
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            fieldFocused = true
                        }
                    }
            } else {
                Button(action: onTapName) {
                    HStack(spacing: LS.xs) {
                        Text(config.displayName)
                            .font(.lsBody)
                            .foregroundStyle(config.isEnabled ? Color.lsPrimary : Color.lsSecondary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.lsTertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Toggle("", isOn: $config.isEnabled)
                .labelsHidden()
                .tint(Color.lsBlue)
                .frame(width: 51)
                .onChange(of: config.isEnabled) { _, _ in HapticEngine.shared.tap() }
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .contentShape(Rectangle())
        .onChange(of: isEditing) { _, editing in
            if !editing { commitName() }
        }
    }

    private func commitName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        config = PeriodConfig(id: config.id, customName: trimmed,
                              colorIndex: config.colorIndex, isEnabled: config.isEnabled)
        fieldFocused = false
        if isEditing { onTapName() }
    }
}

// MARK: - Color Picker Popup

private struct ColorPickerPopup: View {
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    private let columns = Array(repeating: GridItem(.fixed(40), spacing: LS.sm), count: 5)

    var body: some View {
        VStack(spacing: LS.sm) {
            Text("Choose a Color")
                .font(.lsCaption)
                .foregroundStyle(Color.lsSecondary)
                .padding(.top, LS.sm)
            LazyVGrid(columns: columns, spacing: LS.sm) {
                ForEach(ColorPalette.colors) { paletteColor in
                    let isSelected = paletteColor.id == selectedIndex
                    Button { onSelect(paletteColor.id) } label: {
                        Circle()
                            .fill(Color(hex: paletteColor.hex))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if isSelected {
                                    Circle().strokeBorder(Color.white, lineWidth: 2.5)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .shadow(color: Color(hex: paletteColor.hex).opacity(0.5),
                                    radius: isSelected ? 6 : 0)
                    }
                    .buttonStyle(.plain)
                    .animation(.lsSnappy, value: isSelected)
                }
            }
            .padding(.horizontal, LS.md)
            .padding(.bottom, LS.md)
        }
        .frame(width: 240)
        .background(Color.lsSurface)
    }
}

#Preview {
    SettingsSheetView(settings: UserSettings.shared)
        .environment(CalendarStore())
}

// MARK: - Pre-warm

struct ColorPickerPrewarm: View {
    @State private var dummy = false
    @FocusState private var dummyFocus: Bool
    var body: some View {
        TextField("", text: .constant("")).focused($dummyFocus)
        Color.clear.popover(isPresented: $dummy) { Color.clear.frame(width: 1, height: 1) }
    }
}
