//
//  SettingsSheetView.swift
//  LHS Life
//
//  settings is passed as a parameter — never use a custom init() with @Bindable,
//  as it breaks SwiftUI view identity and causes full reconstruction on first open.
//

import SwiftUI

struct SettingsSheetView: View {
    // Passed in directly so SwiftUI can track identity without a custom init.
    @Bindable var settings: UserSettings
    @Environment(\.dismiss) private var dismiss

    @State private var editingPeriodID: Int? = nil
    @FocusState private var gradYearFocused: Bool
    @State private var gradYearInput = ""
    @State private var isEditingGradYear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: LS.lg, pinnedViews: []) {
                    gradYearSection
                    periodsSection
                    notificationsSection
                }
                .padding(.horizontal, LS.md)
                .padding(.top, LS.sm)
                .padding(.bottom, LS.xxl)
            }
            .background(Color.lsSurface)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveAndDismiss() }
                        .font(.lsHeadline)
                        .foregroundStyle(Color.lsBlue)
                }
            }
        }
        .onDisappear { settings.save() }
    }

    private func saveAndDismiss() {
        commitGradYear()
        settings.save()
        dismiss()
    }

    // MARK: - Grad Year

    private var gradYearSection: some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel("My Info")
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Graduation Year")
                        .font(.lsHeadline)
                        .foregroundStyle(Color.lsPrimary)
                    Text("Determines Pathways Day eligibility")
                        .font(.lsCaption)
                        .foregroundStyle(Color.lsSecondary)
                }
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

                Divider().background(Color.lsTertiary.opacity(0.3))

                Toggle(isOn: $settings.liveActivityEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Activity")
                            .font(.lsHeadline)
                            .foregroundStyle(Color.lsPrimary)
                        Text("Show current period in Dynamic Island")
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                    }
                }
                .tint(Color.lsBlue)
                .padding(LS.md)
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

            Button { showColorPicker = true } label: {
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
