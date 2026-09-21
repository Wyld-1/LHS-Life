//
//  SettingsSheetView.swift
//  LHS Life
//
//  A stock iOS grouped list. The previous version built its own cards,
//  section labels, dividers, capsule pop-up buttons and inline edit states —
//  all of it a hand-made imitation of what List already does, and all of it
//  one more thing to keep visually in sync with the rest of the app.
//
//  Settings is the one screen where being unremarkable is the whole job:
//  students already know how iOS Settings works, so anything we invent here
//  is something they have to learn for no benefit. The previous version is
//  kept at Docs/legacy/SettingsSheetView-cards.swift.orig.
//
//  Three interactions changed shape because the native idiom is better:
//    - Graduation year: was an inline text field that swapped places with a
//      chip. Now a menu (Enter Year… / Not a Student) plus an alert.
//    - Class names: were tap-to-edit, one row at a time, with focus juggling.
//      Now always-editable text fields, the way Contacts edits a card.
//  ASB working days deliberately kept their tappable pills: five weekdays with
//  three states each is a grid, and a grid wants to be seen at a glance rather
//  than navigated to.
//

import SwiftUI
import UserNotifications
import ActivityKit
import UIKit

struct SettingsSheetView: View {

    @Bindable var settings: UserSettings
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var apModeEnabled = false
    @State private var showGradYearAlert = false
    @State private var gradYearInput = ""
    @State private var showSignOutDialog = false
    @State private var showPrivacyPolicy = false
    @State private var showMapSheet = false

    // Debug-only state. Mirrors DebugClock, which outlives this view.
    @State private var debugTimeEnabled = false
    @State private var debugTimeValue = Date()
    @State private var debugForceTextEnabled = false
    @State private var debugPrimaryText = "22 min left in Period 3"
    @State private var debugSecondaryText = "Next: Lunch at 11:45"
    @State private var debugProgress: Double = 0.6

    var body: some View {
        NavigationStack {
            List {
                apExamSection
                myInfoSection
                classesSection
                alertsSection
                mapSection
                #if DEBUG
                debugSection
                #endif
                signOutSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.apModeEnabledToday = apModeEnabled
                        settings.save()
                        HapticEngine.shared.success()
                        dismiss()
                    }
                }
            }
        }
        .tint(Color.lsBlue)
        .onAppear {
            apModeEnabled = settings.apModeEnabledToday
            // Sync FROM the DebugClock singleton, not just to it — it
            // outlives this view (recreated fresh every time Settings opens),
            // so without this the toggle shows "off" while an override might
            // still be active underneath, and re-toggling would reset it to
            // "right now" instead of restoring whatever was set before.
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
        .alert("Graduation Year", isPresented: $showGradYearAlert) {
            TextField("2029", text: $gradYearInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Save") { commitGradYear() }
        } message: {
            Text("The year you graduate. Sets your class for class-specific alerts.")
        }
        .confirmationDialog(
            "Sign Out of LHS Life?",
            isPresented: $showSignOutDialog,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                HapticEngine.shared.success()
                DataResetService.deleteAllData(settings: settings)
            }
            Button("Sign Out", role: .destructive) {
                HapticEngine.shared.success()
                settings.signOut()
            }
        } message: {
            Text("Sign Out clears your email and grad year. Delete All Data resets all customizations and signs you out of PowerSchool, Schoology, and lunch ordering.")
        }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView() }
        .sheet(isPresented: $showMapSheet) {
            MapTabView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - AP Exam

    @ViewBuilder
    private var apExamSection: some View {
        let dayKey = DateFormatter.isoDay.string(from: Date())
        let examState = APExamService.examState(
            for: dayKey,
            events: store.events(on: dayKey),
            settings: settings
        )
        switch examState {
        case .mine(let name, _, _, let config):
            let color = config.map { Color.paletteColor(for: $0) } ?? Color.lsBlue
            Section {
                APExamBanner(
                    examName: name,
                    isSilenced: apModeEnabled,
                    accentColor: color,
                    onToggle: { HapticEngine.shared.tap(); apModeEnabled.toggle() }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        case .someoneElses(let name, _):
            Section {
                APExamBanner(
                    examName: name,
                    isSilenced: apModeEnabled,
                    accentColor: Color.lsBlue,
                    onToggle: { HapticEngine.shared.tap(); apModeEnabled.toggle() }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - My Info

    private var myInfoSection: some View {
        Section("My Info") {
            LabeledContent("Class Of") {
                Menu {
                    Button("Enter Year...") {
                        // Restores the last real year for someone who tapped
                        // "Not a student" and came back, rather than starting
                        // them from an empty field.
                        let prefill = settings.prefillGraduationYear
                        gradYearInput = prefill == 0 ? "" : String(prefill)
                        showGradYearAlert = true
                    }
                    Divider()
                    Button("Not a Student") { setNotAStudent() }
                } label: {
                    // .tint, not .secondary: the Live Activities picker one
                    // section down renders its value in the tint color, and a
                    // gray value next to a blue one reads as disabled.
                    HStack(spacing: LS.xs) {
                        Text(gradYearLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.tint)
                }
            }
        }
    }

    private var gradYearLabel: String {
        settings.isStudent ? String(settings.graduationYear) : "Not a student"
    }

    private func setNotAStudent() {
        // setGraduationYear stashes the outgoing year first, so Enter Year…
        // can bring it back.
        settings.setGraduationYear(0)
        // ASB is student leadership — the toggle disappears below when
        // isStudent is false, so clear it rather than leaving it stuck on and
        // invisibly scheduling reminders.
        settings.isASBMember = false
        HapticEngine.shared.tick()
    }

    private func commitGradYear() {
        guard let year = Int(gradYearInput.trimmingCharacters(in: .whitespaces)),
              year > 2020, year < 2040, year != settings.graduationYear else { return }
        settings.setGraduationYear(year)
        HapticEngine.shared.tick()
    }

    // MARK: - My Classes

    private var classesSection: some View {
        Section {
            ForEach($settings.periodConfigs) { $config in
                PeriodRow(config: $config)
            }
        } header: {
            Text("My Classes")
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Section {
            Toggle("Professional Dress", isOn: $settings.professionalDressNotificationsEnabled)
                .onChange(of: settings.professionalDressNotificationsEnabled) { _, _ in
                    HapticEngine.shared.tap()
                }

            Picker("Live Activities", selection: $settings.liveActivityMode) {
                ForEach(LiveActivityMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: settings.liveActivityMode) { _, _ in HapticEngine.shared.tick() }

            // ASB is student leadership only — hidden entirely for staff and
            // parents rather than shown-and-disabled, since there's no path by
            // which a non-student would want it.
            if settings.isStudent {
                Toggle("ASB Member", isOn: $settings.isASBMember)
                    .onChange(of: settings.isASBMember) { _, _ in HapticEngine.shared.tap() }

                if settings.isASBMember {
                    // Inline, tappable, one tap per state — deliberately not a
                    // sub-screen. Five weekdays with three states each is a
                    // grid, and a grid wants to be seen all at once; burying it
                    // behind a disclosure turns "glance and adjust" into
                    // "navigate, adjust, go back."
                    ASBWorkingDaysRow(settings: settings)
                        .listRowInsets(EdgeInsets(top: LS.sm, leading: LS.md,
                                                  bottom: LS.sm, trailing: LS.md))
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Professional Dress reminds you at 9:00 PM the evening before. Live Activities pin the live bell schedule to your Lock Screen.")
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Section("Map") {
            Toggle("Show Map in Tab Bar", isOn: $settings.showMapTab)
                .onChange(of: settings.showMapTab) { _, _ in HapticEngine.shared.tap() }

            Button {
                if settings.showMapTab {
                    // Tab is visible — navigate to it.
                    settings.save()
                    dismiss()
                    AppNavigationCoordinator.shared.pendingTab = .map
                } else {
                    // Tab is hidden — open as a sheet so anyone can still see it.
                    showMapSheet = true
                }
            } label: {
                Label("Open Campus Map", systemImage: "map.fill")
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section {
            // Screenshot tool: forces the header pill's rendered text and
            // progress directly, bypassing the real schedule-state
            // computation. Faking a "now" that flows correctly through
            // schedule lookup + engine + period matching is fragile for a
            // one-off screenshot; forcing the output can't produce nonsense
            // regardless of what schedule data does or doesn't exist.
            Toggle("Force Header Text", isOn: $debugForceTextEnabled)
                .onChange(of: debugForceTextEnabled) { _, enabled in
                    DebugClock.shared.forcedPrimaryText = enabled ? debugPrimaryText : nil
                    DebugClock.shared.forcedSecondaryText = enabled
                        ? (debugSecondaryText.isEmpty ? nil : debugSecondaryText) : nil
                    DebugClock.shared.forcedProgress = enabled ? debugProgress : nil
                }

            if debugForceTextEnabled {
                TextField("Primary text", text: $debugPrimaryText)
                    .onChange(of: debugPrimaryText) { _, new in
                        DebugClock.shared.forcedPrimaryText = new
                    }
                TextField("Secondary text (optional)", text: $debugSecondaryText)
                    .onChange(of: debugSecondaryText) { _, new in
                        DebugClock.shared.forcedSecondaryText = new.isEmpty ? nil : new
                    }
                LabeledContent("Progress") {
                    HStack {
                        Slider(value: $debugProgress, in: 0...1)
                            .onChange(of: debugProgress) { _, new in
                                DebugClock.shared.forcedProgress = new
                            }
                        Text("\(Int(debugProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Toggle("Override Now-Ticker Date", isOn: $debugTimeEnabled)
                .onChange(of: debugTimeEnabled) { _, enabled in
                    DebugClock.shared.overrideDate = enabled ? debugTimeValue : nil
                }

            if debugTimeEnabled {
                DatePicker("Fake time", selection: $debugTimeValue,
                           displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: debugTimeValue) { _, new in
                        DebugClock.shared.overrideDate = new
                    }
                Button("Inject Regular Schedule for This Date") {
                    store.debugInjectRegularSchedule(for: debugTimeValue)
                }
            }

            Button("Send Announcement Notification") {
                Task {
                    let content = UNMutableNotificationContent()
                    content.title = "Morning Announcements"
                    content.body  = "> This is a DEBUG test"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
                    try? await UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: "debug-announcement",
                                              content: content, trigger: trigger)
                    )
                }
            }

            Button("Force Start Live Activity (Dummy)") {
                LiveActivityService.shared.startDummy()
            }

            Button("Force Start Live Activity (Real)") {
                let dayKey = DateFormatter.isoDay.string(from: Date())
                LiveActivityService.shared.startIfNeeded(
                    schedule: store.bellSchedules[dayKey],
                    settings: settings
                )
                print("[Debug] Real start attempted")
            }

            Button("Simulate Server Full") {
                LiveActivityService.shared.simulateOverCapacity()
                dismiss()
            }

            Button("End Live Activity", role: .destructive) {
                Task {
                    for activity in Activity<ScheduleActivityAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Debug builds only. None of this ships to students.")
        }
    }
    #endif

    // MARK: - Sign Out / About

    private var signOutSection: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                showSignOutDialog = true
            }
        }
    }

    private var aboutSection: some View {
        Section {
            // Apple requires the policy to be reachable from inside the app;
            // it opens as a sheet rather than sending a student to a browser.
            Button("Privacy Policy") {
                showPrivacyPolicy = true
            }
        } footer: {
            Text("LHS Life \(Self.versionString)· La Salle High School · Yakima")
        }
    }

    private static var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Period Row

private struct PeriodRow: View {

    @Binding var config: PeriodConfig
    @State private var showColorPicker = false

    var body: some View {
        HStack(spacing: LS.md) {
            Text(String(config.id))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .center)

            Button {
                showColorPicker = true
            } label: {
                Circle()
                    .fill(Color.paletteColor(for: config))
                    .frame(width: 22, height: 22)
                    .lsSphereRim()
            }
            .buttonStyle(.plain)
            .opacity(config.isEnabled ? 1.0 : 0.4)
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                ColorPickerPopup(selectedIndex: config.colorIndex) { index in
                    config = PeriodConfig(id: config.id, customName: config.customName,
                                          colorIndex: index, isEnabled: config.isEnabled)
                    showColorPicker = false
                    HapticEngine.shared.tick()
                }
                .presentationCompactAdaptation(.popover)
            }

            // Always editable — no tap-to-edit state, no focus juggling. The
            // placeholder carries the period number when there's no name yet.
            TextField(config.id == 0 ? "Period 0" : "Period \(config.id)",
                      text: Binding(
                        get: { config.customName },
                        set: { config = PeriodConfig(id: config.id, customName: $0,
                                                     colorIndex: config.colorIndex,
                                                     isEnabled: config.isEnabled) }
                      ))
            .foregroundStyle(config.isEnabled ? Color.primary : Color.secondary)
            .submitLabel(.done)

            Toggle("", isOn: $config.isEnabled)
                .labelsHidden()
                .onChange(of: config.isEnabled) { _, _ in HapticEngine.shared.tap() }
        }
    }
}

// MARK: - ASB Working Days

/// Five weekdays, three states each, tapped to cycle: Off → Announcements &
/// Store → Announcements → Off. The legend underneath is what makes the colors
/// readable; without it the row is a puzzle.
private struct ASBWorkingDaysRow: View {

    @Bindable var settings: UserSettings

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]

    var body: some View {
        VStack(alignment: .leading, spacing: LS.md) {
            Text("Working days")
                .font(.lsCaption)
                .foregroundStyle(.secondary)

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

            VStack(alignment: .leading, spacing: LS.xs) {
                ForEach(ASBDayMode.allCases.filter { $0 != .off }, id: \.rawValue) { m in
                    HStack(spacing: LS.xs) {
                        Circle()
                            .fill(Color(hex: m.color))
                            .frame(width: 8, height: 8)
                        Text(m.label)
                            .font(.lsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, LS.xs)
    }
}

// MARK: - Color Picker Popup

private struct ColorPickerPopup: View {
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    // Sized so the grid exactly fills the frame: 5 × 34 + 4 × 10 + 2 × 14 = 238.
    private static let dot: CGFloat = 34
    private static let gap: CGFloat = 10
    private static let inset: CGFloat = 14
    private static let width: CGFloat = (dot * 5) + (gap * 4) + (inset * 2)

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Self.gap) {
            ForEach(ColorPalette.colors) { paletteColor in
                let color = Color(hex: paletteColor.hex)
                let isSelected = paletteColor.id == selectedIndex
                Button { onSelect(paletteColor.id) } label: {
                    Circle()
                        .fill(color)
                        .frame(width: Self.dot, height: Self.dot)
                        .lsSphereRim()
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(Color.white, lineWidth: 2.5)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .lsTintShadow(color, opacity: isSelected ? 0.55 : 0.30)
                }
                .buttonStyle(.plain)
                .animation(.lsSnappy, value: isSelected)
            }
        }
        .padding(Self.inset)
        .frame(width: Self.width)
        // SwiftUI gives no API for the popover's arrow color — presentation
        // background paints the content rect only, and the system keeps
        // drawing the arrow from its own backdrop. Over-extending the
        // background with negative padding bleeds it into the arrow's area.
        .background(Color.lsSurface.padding(-80))
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
