//
//  PhoneContactsSheet.swift
//  LHS Life
//
//  iPhone-only — school iPads can't place calls, so this never appears there.
//  Presented from the phone button in the iPhone toolbar.
//
//  Two sections:
//    Office   — LaSalle's main office number
//    Support  — Upper Room (Catholic crisis, 24/7), Teen Link (WA peer line),
//               and 988 (national crisis lifeline)
//
//  iOS presents its native "Call {number}?" confirmation sheet on tap —
//  we never display the raw digits ourselves.
//

import SwiftUI
import UIKit

struct PhoneContactsSheet: View {

    @Environment(\.dismiss) private var dismiss

    // MARK: - Data

    private struct Contact {
        let label: String
        let detail: String?
        let number: String
        let color: Color
    }

    private static let office: [Contact] = [
        .init(
            label: "LaSalle Office",
            detail: nil,
            number: "5092252900",
            color: Color.lsBlue
        ),
    ]

    private static let support: [Contact] = [
        .init(
            label: "Upper Room Crisis Hotline",
            detail: "A faith-based hotline in the Catholic Tradition. God's Love Has A Toll Free Number.",
            number: "8888088724",
            color: Color.lsGold
        ),
        .init(
            label: "Teen Link",
            detail: "Connects teens with other teens who understand what they're going through. Teen volunteers are there to listen and help with anything.",
            number: "8668336546",
            color: Color.lsSuccess
        ),
        .init(
            label: "988 Suicide & Crisis Lifeline",
            detail: "Get help right now for yourself or a loved one. Call or text 988.",
            number: "988",
            color: Color.lsDestructive
        ),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Sheet handle + header
            HStack {
                Text("Contact")
                    .font(.lsTitle)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.lsHeadline)
                    .foregroundStyle(Color.lsBlue)
            }
            .padding(.horizontal, LS.md)
            .padding(.top, LS.lg)
            .padding(.bottom, LS.md)

            Rectangle()
                .fill(Color.lsTertiary.opacity(LSDivider.sectionOpacity))
                .frame(height: LSDivider.thickness)

            ScrollView {
                VStack(spacing: LS.lg) {
                    contactSection(label: "Office", contacts: Self.office)
                    contactSection(label: "Support", contacts: Self.support)
                }
                .padding(.horizontal, LS.md)
                .padding(.vertical, LS.md)
            }
        }
        .background(Color.lsSurface)
    }

    // MARK: - Helpers

    private func contactSection(label: String, contacts: [Contact]) -> some View {
        VStack(alignment: .leading, spacing: LS.sm) {
            sectionLabel(label)

            VStack(spacing: 0) {
                ForEach(Array(contacts.enumerated()), id: \.offset) { index, contact in
                    if index > 0 {
                        rowDivider
                    }
                    contactRow(contact)
                }
            }
            .lsCard()
        }
    }

    /// Section chrome comes from DesignSystem (LSSectionLabel / LSRowDivider)
    /// — these thin wrappers exist only so the call sites below read the same
    /// as SettingsSheetView's.
    private func sectionLabel(_ text: String) -> some View {
        LSSectionLabel(text: text)
    }

    private var rowDivider: some View { LSRowDivider() }

    private func contactRow(_ contact: Contact) -> some View {
        Button { makeCall(contact.number) } label: {
            HStack(alignment: contact.detail == nil ? .center : .top, spacing: LS.md) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(contact.color)
                    .padding(.top, contact.detail != nil ? 2 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.label)
                        .font(.lsHeadline)
                        .foregroundStyle(contact.color)
                    if let detail = contact.detail {
                        Text(detail)
                            .font(.lsCaption)
                            .foregroundStyle(Color.lsSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(LS.md)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func makeCall(_ number: String) {
        let digits = number.filter { $0.isNumber }
        guard let url = URL(string: "tel://\(digits)"),
              UIApplication.shared.canOpenURL(url) else { return }
        HapticEngine.shared.tap()
        UIApplication.shared.open(url)
    }
}

#Preview {
    PhoneContactsSheet()
}
