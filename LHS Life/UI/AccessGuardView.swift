//
//  AccessGuardView.swift
//  LHS Life
//
//  Shown exactly once on first launch. Never seen again after approval.
//  Validates that the entered email ends in @lasalleyakima.org.
//  No network call — purely local string check.
//  Wrong domain: shows an error, field stays open, no lockout.
//

import SwiftUI

struct AccessGuardView: View {

    @Bindable var settings: UserSettings

    @State private var email        = ""
    @State private var showError    = false
    @State private var shaking      = false
    @FocusState private var focused: Bool

    private static let allowedDomain = "@lasalleyakima.org"

    var body: some View {
        ZStack {
            Color.lsBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Logo + wordmark
                VStack(spacing: LS.md) {
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 90, height: 90)

                    VStack(spacing: LS.sm) {
                        Text("LHS Life")
                            .font(.lsDisplay)
                            .foregroundStyle(Color.lsPrimary)
                        Text("LA SALLE HIGH SCHOOL · YAKIMA")
                            .font(.lsLabel)
                            .foregroundStyle(Color.lsSecondary)
                            .tracking(2)
                    }
                }

                Spacer()

                // MARK: Email entry card
                VStack(spacing: LS.lg) {
                    Text("Enter your school email to continue")
                        .font(.lsHeadline)
                        .foregroundStyle(Color.lsPrimary)

                    // Email field
                    VStack(spacing: LS.xs) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundStyle(Color.lsSecondary)
                                .frame(width: 20)
                            TextField("My email...", text: $email)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.go)
                                .focused($focused)
                                .onSubmit { attempt() }
                                .foregroundStyle(Color.lsPrimary)
                        }
                        .padding(LS.md)
                        .background(Color.lsSurfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous)
                                .strokeBorder(
                                    showError ? Color.lsDestructive : Color.clear,
                                    lineWidth: 1.5
                                )
                        }
                        .offset(x: shaking ? -8 : 0)
                        .animation(.default, value: shaking)

                        // Error message
                        if showError {
                            HStack(spacing: LS.xs) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                Text("Use your LaSalle email")
                                    .font(.lsCaption)
                            }
                            .foregroundStyle(Color.lsDestructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, LS.xs)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.lsSnappy, value: showError)

                    // Continue button
                    Button(action: attempt) {
                        Text("Continue")
                            .font(.lsHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LS.md)
                            .background(
                                email.isEmpty
                                    ? Color.lsBlue.opacity(0.4)
                                    : Color.lsBlue
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(LS.xl)
                .background(Color.lsSurface)
                .clipShape(RoundedRectangle(cornerRadius: LS.radiusXl, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 32, y: 8)
                .padding(.horizontal, LS.lg)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }

    // MARK: - Validation

    private func attempt() {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasSuffix(Self.allowedDomain),
              trimmed.count > Self.allowedDomain.count else {
            reject()
            return
        }

        // Parse grad year from email prefix.
        // Format: [initial][lastname][2-digit-year]@lasalleyakima.org
        // e.g. llefohn27 → 2027
        let prefix = String(trimmed.prefix(trimmed.count - Self.allowedDomain.count))
        if let gradYear = extractGradYear(from: prefix) {
            settings.graduationYear = gradYear
        } else {
            settings.graduationYear = 0
        }

        HapticEngine.shared.success()
        settings.schoolEmail = trimmed
        settings.accessApproved = true
        settings.save()
    }

    /// Extracts a 4-digit grad year from the email local part.
    /// Rolls forward by century until the year is not in the past.
    /// Y3K compatible. You're welcome.
    private func extractGradYear(from prefix: String) -> Int? {
        let digits = prefix.reversed().prefix(while: { $0.isNumber })
        guard digits.count >= 2 else { return nil }
        let twoDigits = String(digits.prefix(2).reversed())
        guard let twoDigitInt = Int(twoDigits) else { return nil }

        let currentYear = Calendar.current.component(.year, from: Date())
        var century = (currentYear / 100) * 100
        while true {
            let year = century + twoDigitInt
            if year >= currentYear { return year }
            century += 100
        }
    }

    private func reject() {
        HapticEngine.shared.bump()
        withAnimation(.lsSnappy) { showError = true }
        // Shake the field
        withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) {
            shaking = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shaking = false }
    }
}

#Preview {
    AccessGuardView(settings: UserSettings.shared)
        .environment(UserSettings.shared)
}
