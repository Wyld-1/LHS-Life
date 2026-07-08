//
//  APExamBanner.swift
//  LHS Life
//
//  (Relocated from UI/Components/ScheduleHeader.swift — that file's other
//  contents were all iPhone/old-iPad header pieces that have since moved
//  or been removed; this banner is genuinely shared, so it gets an honest
//  home and an honest name.)
//
//  Used by SettingsSheetView's AP exam section, on both platforms.
//

import SwiftUI

struct APExamBanner: View {
    let examName: String
    let isSilenced: Bool
    let accentColor: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LS.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(examName)
                    .font(.lsHeadline)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(isSilenced ? "AP Mode on" : "AP Mode off")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.lsSecondary)
            }
            Spacer()
            Button(action: onToggle) {
                Text(isSilenced ? "Exit AP Mode" : "AP Mode")
                    .font(.lsLabel)
                    .foregroundStyle(.white)
                    .padding(.horizontal, LS.sm)
                    .padding(.vertical, 5)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LS.md)
        .padding(.vertical, LS.sm)
        .background(accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LS.radiusSm, style: .continuous)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .animation(.lsSnappy, value: isSilenced)
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color.lsBackground.ignoresSafeArea()
        APExamBanner(
            examName: "AP Calculus BC",
            isSilenced: false,
            accentColor: Color.lsBlue,
            onToggle: {}
        )
        .padding(.horizontal, LS.md)
        .padding(.top, LS.sm)
    }
}
