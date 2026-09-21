//
//  PrivacyPolicyView.swift
//  LHS Life
//
//  Renders Resources/PRIVACY.md inside the app. Apple requires the policy to
//  be reachable from within the app; sending a student out to GitHub to read
//  it is both a worse experience and a link that breaks the day the repo
//  moves. The Markdown file is the single source of truth — edit it, and this
//  screen follows. App Store Connect still needs its own hosted copy of the
//  same text.
//
//  The renderer covers exactly what PRIVACY.md uses: headings, paragraphs,
//  bullets, and one table. Inline bold/italic/links come free from
//  AttributedString's Markdown parser. Anything it doesn't recognize falls
//  through as a paragraph rather than disappearing.
//

import SwiftUI

struct PrivacyPolicyView: View {

    @Environment(\.dismiss) private var dismiss

    private let blocks: [PolicyBlock] = PolicyDocument.load()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Privacy")
                    .font(.lsTitle)
                    .foregroundStyle(Color.lsPrimary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
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
                VStack(alignment: .leading, spacing: LS.md) {
                    ForEach(blocks) { block in
                        view(for: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LS.md)
                .padding(.top, LS.md)
                .padding(.bottom, LS.xxl)
            }
        }
        .background(Color.lsSurface)
    }

    @ViewBuilder
    private func view(for block: PolicyBlock) -> some View {
        switch block.kind {
        case .title:
            Text(block.text)
                .font(.lsDisplay)
                .foregroundStyle(Color.lsPrimary)
                .padding(.top, LS.sm)

        case .heading:
            Text(block.text)
                .font(.lsTitle)
                .foregroundStyle(Color.lsPrimary)
                .padding(.top, LS.md)

        case .paragraph:
            Text(inline(block.text))
                .font(.lsBody)
                .foregroundStyle(Color.lsPrimary)
                .tint(Color.lsBlue)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: LS.sm) {
                Circle()
                    .fill(Color.lsBlue)
                    .frame(width: 5, height: 5)
                    .offset(y: -3)
                Text(inline(block.text))
                    .font(.lsBody)
                    .foregroundStyle(Color.lsPrimary)
                    .tint(Color.lsBlue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, LS.xs)

        case .tableRow:
            // Two-column Markdown tables don't fit a phone. Each row becomes a
            // card: left cell as the label, right cell as the explanation.
            VStack(alignment: .leading, spacing: LS.xs) {
                Text(inline(block.text))
                    .font(.lsHeadline)
                    .foregroundStyle(Color.lsPrimary)
                Text(inline(block.secondary))
                    .font(.lsCaption)
                    .foregroundStyle(Color.lsSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LS.md)
            .background(Color.lsSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: LS.radiusMd, style: .continuous))
        }
    }

    /// Bold, italics, and links, courtesy of Foundation. Falls back to the raw
    /// string if the line isn't valid Markdown.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Document model

struct PolicyBlock: Identifiable {
    enum Kind { case title, heading, paragraph, bullet, tableRow }

    let id = UUID()
    let kind: Kind
    let text: String
    var secondary: String = ""
}

enum PolicyDocument {

    /// Parses the bundled Markdown once, at first use.
    static func load() -> [PolicyBlock] {
        guard let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return [PolicyBlock(
                kind: .paragraph,
                text: "The privacy policy couldn't be loaded. Please contact La Salle High School ASB."
            )]
        }
        return parse(raw)
    }

    static func parse(_ markdown: String) -> [PolicyBlock] {
        var blocks: [PolicyBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            paragraph.removeAll()
            guard !joined.isEmpty else { return }
            blocks.append(PolicyBlock(kind: .paragraph, text: joined))
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { flushParagraph(); continue }

            if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(PolicyBlock(kind: .heading, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(PolicyBlock(kind: .title, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(PolicyBlock(kind: .bullet, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("|") {
                flushParagraph()
                let cells = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // Skip the |---|---| separator and the header row: the section
                // heading above the table already says what the columns are.
                let isSeparator = cells.allSatisfy { $0.allSatisfy { ch in ch == "-" || ch == ":" } }
                let isHeader = cells == ["Data", "Why"]
                if !isSeparator && !isHeader && cells.count >= 2 {
                    blocks.append(PolicyBlock(kind: .tableRow, text: cells[0], secondary: cells[1]))
                }
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

#Preview {
    PrivacyPolicyView()
}
