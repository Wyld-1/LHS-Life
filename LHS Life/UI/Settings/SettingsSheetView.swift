//
//  SettingsSheetView.swift
//  LHS Life
//
//  No NavigationStack — that's the primary source of first-open latency.
//  NavigationStack inside a sheet allocates a full navigation state machine
//  on first render. We don't use navigation here, so we don't pay for it.
//  A plain VStack header gives us the title and Done button with zero overhead.
//

import SwiftUI

struct SettingsSheetView: View {
    @Bindable var settings: UserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var editingPeriodID: Int? = nil
    @FocusState private var gradYearFocused: Bool
    @State private var gradYearInput = ""
    @State private var isEditingGradYear = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header — replaces NavigationStack overhead
            HStack {
                Text("Settings")
                    .font(.lsTitle)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                Button("Done") {
                    commitGradYear()
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

            // MARK: Content
            ScrollView {
                LazyVStack(spacing: LS.lg, pinnedViews: []) {
                    gradYearSection
                    asbSection
                    periodsSection
                    notificationsSection
                }
                .padding(.horizontal, LS.md)
                .padding(.top, LS.md)
                .padding(.bottom, LS.xxl)
            }
        }
        .background(Color.lsSurface)
        .onDisappear { settings.save() }
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

    // MARK: - ASB

    private static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]

    private var asbSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            // ASB toggle lives inside the My Info card
            VStack(spacing: 0) {
                Toggle(isOn: $settings.isASBMember) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ASB Member")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Enables student leadership notifications")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: settings.isASBMember) { _, _ in HapticEngine.shared.tap() }

                // Work days — revealed when ASB is on
                if settings.isASBMember {
                    Divider().background(Color.lsTertiary.opacity(0.3))

                    VStack(alignment: .leading, spacing: LS.sm) {
                        Text("I work Student Store on:")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .padding(.horizontal, LS.md)
                            .padding(.top, LS.sm)

                        HStack(spacing: LS.sm) {
                            ForEach(0..<5, id: \.self) { i in
                                Button {
                                    HapticEngine.shared.tick()
                                    settings.asbWorkDays[i].toggle()
                                } label: {
                                    Text(Self.weekdayNames[i])
                                        .font(.lsCaption)
                                        .foregroundStyle(settings.asbWorkDays[i] ? .white : Color.lsSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, LS.xs + 2)
                                        .background(
                                            settings.asbWorkDays[i]
                                                ? Color.lsBlue
                                                : Color.lsSurfaceRaised
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .animation(.lsSnappy, value: settings.asbWorkDays[i])
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

    // MARK: - Notifications

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

                Toggle(isOn: $settings.liveActivityEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Activities")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Show current period in Dynamic Island")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
                .onChange(of: settings.liveActivityEnabled) { _, _ in
                    HapticEngine.shared.tap()
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
        config = PeriodConfig(
            id: config.id,
            customName: trimmed,
            colorIndex: config.colorIndex,
            isEnabled: config.isEnabled
        )
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
}

// MARK: - Pre-warm view
// Rendered hidden at app launch so SwiftUI initializes the popover presentation
// system and @FocusState machinery before the user first opens settings.
// Cost: essentially zero. Benefit: first edit and first color tap are instant.
struct ColorPickerPrewarm: View {
    @State private var dummy = false
    @FocusState private var dummyFocus: Bool
    var body: some View {
        // One TextField to warm @FocusState registration
        TextField("", text: .constant(""))
            .focused($dummyFocus)
        // One popover to warm the popover presentation system
        Color.clear
            .popover(isPresented: $dummy) { Color.clear.frame(width: 1, height: 1) }
    }
}
