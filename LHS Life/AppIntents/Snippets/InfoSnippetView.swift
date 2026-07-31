//
//  InfoSnippetView.swift
//  LHS Life
//
//  Compact Siri/Shortcuts snippet for non-progress answers (today's schedule,
//  evening events, next professional dress day). Same rules as
//  ClassStatusSnippetView: no background/card chrome — the system container
//  already provides that — and no local state, since this is recreated on
//  every render.
//

import SwiftUI

struct InfoSnippetView: View {
    let title: String
    let symbolName: String
    let color: Color
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbolName)
                .font(.headline)
                .foregroundStyle(color)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
