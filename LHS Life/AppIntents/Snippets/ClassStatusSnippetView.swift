//
//  ClassStatusSnippetView.swift
//  LHS Life
//
//  Compact Siri/Shortcuts snippet showing the current or next class.
//  Deliberately minimal — the system already wraps this in its own native
//  container (rounded corners, materials, spacing), so this view supplies
//  content only: no background, no card chrome, no custom corner radius.
//  Recreated on every render per App Intents' snippet lifecycle, so it must
//  stay a pure function of its inputs — no local state, no mutation.
//

import SwiftUI

struct ClassStatusSnippetView: View {
    let className: String
    let color: Color
    /// 0...1 elapsed fraction of the period. Nil when there's nothing actively
    /// running yet (e.g. showing the next class before school starts).
    let progress: Double?
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(className, systemImage: "book.closed.fill")
                .font(.headline)
                .foregroundStyle(color)
            if let progress {
                ProgressView(value: progress)
                    .tint(color)
            }
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
