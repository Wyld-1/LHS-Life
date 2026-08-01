//
//  SettingsSheetView.swift
//  LHS Life
//

import SwiftUI
import UserNotifications
import ActivityKit

struct SettingsSheetView: View {
    @Bindable var settings: UserSettings
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editingPeriodID: Int? = nil
    @FocusState private var gradYearFocused: Bool
    @State private var gradYearInput = ""
    @State private var isEditingGradYear = false
    @State private var apModeEnabled = false
    @State private var debugTimeEnabled = false
    @State private var debugTimeValue = Date()
    @State private var debugForceTextEnabled = false
    @State private var debugPrimaryText = "22 min left in Period 3"
    @State private var debugSecondaryText = "Next: Lunch at 11:45"
    @State private var debugProgress: Double = 0.6
    @State private var showSignOutDialog = false

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
                    asbSection
                    debugSection
                    signOutSection
                }
                .padding(.horizontal, LS.md)
                .padding(.top, LS.md)
                .padding(.bottom, LS.sm)
            }
        }
        .background(Color.lsSurface)
        .onAppear {
            apModeEnabled = settings.apModeEnabledToday
            // Sync FROM the DebugClock singleton, not just to it — it
            // outlives this view (recreated fresh every time Settings
            // opens), so without this the toggle shows "off" while an
            // override might still silently be active underneath, and
            // re-toggling would reset it to "right now" instead of
            // restoring whatever was actually set before.
            if let override = DebugClock.shared.overrideDate {
                debugTimeEnabled = true
                debugTimeValue = override
            }
            if let forced = DebugClock.shared.forcedPrimaryText {
                debugForceTextEnabled = true
                debugPrimaryText = forced
                debugSecondaryText = DebugClock.shared.forcedSecondaryText ?? ""
            }
            if let progress = DebugClock.shared.forcedProgress {
                debugProgress = progress
            }
        }
        .onDisappear { settings.save() }
        .confirmationDialog(
            "Sign Out of LHS Life?",
            isPresented: $showSignOutDialog,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                HapticEngine.shared.success()
                settings.deleteAllData()
            }
            Button("Sign Out", role: .destructive) {
                HapticEngine.shared.success()
                settings.signOut()
            }
        } message: {
            Text("Sign Out clears your email and grad year. Delete All Data resets all customizations.")
        }
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
                    } label: {
                        Text(String(settings.graduationYear))
                            .font(.lsTime)
                            .foregroundStyle(Color.lsBlue)
                            .padding(.horizontal, LS.sm)
                            .frame(height: LS.chipHeight)
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
        if let year = Int(gradYearInput), year > 2020, year < 2040, year != graduationYearBeforeEdit {
            settings.graduationYear = year
            HapticEngine.shared.tick()
        }
        isEditingGradYear = false
        gradYearFocused = false
    }

    private var graduationYearBeforeEdit: Int { settings.graduationYear }

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
                        Picker("Live Activities", selection: $settings.liveActivityMode) {
                            ForEach(LiveActivityMode.allCases.filter { $0 != .off }, id: \.rawValue) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Divider()
                        Picker("Live Activities", selection: $settings.liveActivityMode) {
                            Text(LiveActivityMode.off.label).tag(LiveActivityMode.off)
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
                        .frame(height: LS.chipHeight)
                        .background(Color.lsBlue.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .tint(Color.lsPrimary)
                    .onChange(of: settings.liveActivityMode) { _, _ in HapticEngine.shared.tick() }
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

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("Debug")
            VStack(spacing: 0) {
                // Screenshot tool: forces the header pill's rendered text/
                // progress directly, bypassing the real schedule-state
                // computation entirely. Faking a "now" that flows correctly
                // through schedule lookup + engine + period matching is
                // fragile for a one-off screenshot; forcing the output
                // directly can't produce nonsense regardless of what
                // schedule data does or doesn't exist. See DebugClock.swift.
                Toggle(isOn: $debugForceTextEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Force Header Text")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Overrides the pill's text + progress directly")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: debugForceTextEnabled) { _, enabled in
                    if enabled {
                        DebugClock.shared.forcedPrimaryText = debugPrimaryText
                        DebugClock.shared.forcedSecondaryText = debugSecondaryText.isEmpty ? nil : debugSecondaryText
                        DebugClock.shared.forcedProgress = debugProgress
                    } else {
                        DebugClock.shared.forcedPrimaryText = nil
                        DebugClock.shared.forcedSecondaryText = nil
                        DebugClock.shared.forcedProgress = nil
                    }
                }

                if debugForceTextEnabled {
                    Divider().background(Color.lsTertiary.opacity(0.3))

                    VStack(alignment: .leading, spacing: LS.sm) {
                        TextField("Primary text", text: $debugPrimaryText)
                            .font(.lsBody)
                            .foregroundStyle(Color.lsPrimary)
                            .onChange(of: debugPrimaryText) { _, newValue in
                                DebugClock.shared.forcedPrimaryText = newValue
                            }
                        TextField("Secondary text (optional)", text: $debugSecondaryText)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .onChange(of: debugSecondaryText) { _, newValue in
                                DebugClock.shared.forcedSecondaryText = newValue.isEmpty ? nil : newValue
                            }
                        HStack {
                            Text("Progress")
                                .font(.lsCaption)
                                .foregroundStyle(Color.lsSecondary)
                            Slider(value: $debugProgress, in: 0...1)
                                .tint(Color.lsBlue)
                                .onChange(of: debugProgress) { _, newValue in
                                    DebugClock.shared.forcedProgress = newValue
                                }
                            Text("\(Int(debugProgress * 100))%")
                                .font(.lsCaption)
                                .foregroundStyle(Color.lsSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(LS.md)

                    Divider().background(Color.lsTertiary.opacity(0.3))
                }

                // Calendar's "Now" ticker — which date it treats as today,
                // and where vertically it sits. Separate from the text/
                // progress force above since the calendar reads real
                // schedule data directly, not the header pill's computation.
                Toggle(isOn: $debugTimeEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Override Now-Ticker Date")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Shows the red Now line on this date/time")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: debugTimeEnabled) { _, enabled in
                    DebugClock.shared.overrideDate = enabled ? debugTimeValue : nil
                }

                if debugTimeEnabled {
                    Divider().background(Color.lsTertiary.opacity(0.3))

                    DatePicker("Fake time", selection: $debugTimeValue, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(Color.lsBlue)
                        .padding(LS.md)
                        .onChange(of: debugTimeValue) { _, newValue in
                            DebugClock.shared.overrideDate = newValue
                        }

                    Divider().background(Color.lsTertiary.opacity(0.3))

                    Button {
                        store.debugInjectRegularSchedule(for: debugTimeValue)
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundStyle(Color.lsSuccess)
                            Text("Inject Regular Schedule for This Date")
                                .font(.lsHeadline)
                                .foregroundStyle(Color.lsSuccess)
                            Spacer()
                        }
                        .padding(LS.md)
                    }

                    Divider().background(Color.lsTertiary.opacity(0.3))
                }

                #if DEBUG
                Button {
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
                #endif
                
                Button {
                    LiveActivityService.shared.startDummy()
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.lsLabel)
            .foregroundStyle(Color.lsSecondary)
            .tracking(1)
            .padding(.leading, LS.xs)
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button {
            HapticEngine.shared.tap()
            showSignOutDialog = true
        } label: {
            HStack {
                Spacer()
                Text("Sign Out")
                    .font(.lsHeadline)
                    .foregroundStyle(Color.lsDestructive)
                Spacer()
            }
            .padding(LS.md)
        }
        .lsCard()
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
            } label: {
                Circle()
                    .fill(Color.paletteColor(for: config))
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(Color.lsPrimary.opacity(0.12), lineWidth: 1) }
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
