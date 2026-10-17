//
//  CapacityBanner.swift
//  LHS Life
//
//  "Live Activities couldn't start" — shown on any day the school's server
//  turns this device away because it's full.
//
//  The full alert appears only the FIRST time that ever happens (see
//  AppTabContainer). After that, a refusal is old news: repeating an alert
//  every morning would nag a student about something they can't fix. This
//  banner says it quietly instead — at the top of the app on iPhone, in the
//  sidebar on iPad — and can be dismissed for the day. Tapping it explains
//  why and offers the email to ask for an upgrade.
//
//  Self-contained: it reads LiveActivityService.shared, so each layout only
//  has to place it. When the server accepts the device again (the cap was
//  raised), capacityBlock clears and the banner disappears by itself.
//

import SwiftUI

struct CapacityBanner: View {
    @State private var liveActivity = LiveActivityService.shared
    @AppStorage("lhs_capacity_banner_dismissed_day") private var dismissedDay = ""
    @State private var showDetails = false

    private var today: String { DateFormatter.isoDay.string(from: Date()) }
    private var isVisible: Bool { liveActivity.capacityBlock != nil && dismissedDay != today }

    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                Button {
                    showDetails = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text("Live Activities couldn't start")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.lsSnappy) { dismissedDay = today }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss for today")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .sheet(isPresented: $showDetails) {
                // The sheet scrolls, so a half sheet can never clip the
                // title the way it did before the copy was cut down.
                CapacityDetailsSheet(block: liveActivity.capacityBlock)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Details

struct CapacityDetailsSheet: View {
    let block: LiveActivityService.CapacityBlock?
    @Environment(\.dismiss) private var dismiss
    @State private var liveActivity = LiveActivityService.shared

    var body: some View {
        // Scrolls on the smallest phones rather than clipping.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text("Live Activities Are Full")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                Text(CapacityMessage.body(limit: block?.limit))
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    // The hook: most students have never seen a Live Activity.
                    // One look at the card is what makes the upgrade worth asking
                    // for. It runs on this phone alone, so a full server is no
                    // obstacle.
                    if LiveActivityPreviewButton.isAvailable || liveActivity.isPreviewRunning {
                        Button {
                            HapticEngine.shared.tick()
                            if liveActivity.isPreviewRunning {
                                Task { await liveActivity.endPreview() }
                            } else {
                                liveActivity.startPreview()
                            }
                        } label: {
                            Text(liveActivity.isPreviewRunning ? "End Preview" : "Preview Live Activities")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(liveActivity.isPreviewRunning ? Color.lsDestructive : Color.lsBlue)
                                .overlay(Capsule().strokeBorder(
                                    liveActivity.isPreviewRunning ? Color.lsDestructive : Color.lsBlue,
                                    lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        if let hint = LiveActivityPreviewButton.hint {
                            Text(hint)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let url = CapacityMessage.emailURL(to: block?.contact) {
                        Link(destination: url) {
                            Text("Ask for an Upgrade")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.lsBlue, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Button("Not Now") { dismiss() }
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .padding(LS.lg)
            // Room under "Not Now" so it doesn't sit on the sheet's bottom
            // edge at half height.
            .padding(.bottom, LS.lg)
        }
    }
}

// MARK: - Shared wording

/// One source for the explanation and the email, used by the first-time
/// alert and the details sheet so the two can't drift apart.
enum CapacityMessage {
    static func body(limit: Int?) -> String {
        let full = limit.map { "The school's server is full at \($0) devices." } ?? "The school's server is full."
        return """
        \(full) Everything else in LHS Life works normally.

        Want Live Activities? Ask the principal to upgrade the server.
        """
    }

    static func emailURL(to contact: String?) -> URL? {
        guard let contact else { return nil }
        let subject = "Request: upgrade the LHS Life server"
        let body = """
        Hello,

        I'd like to use the live bell schedule on my Lock Screen in LHS Life, but the app says the school's server is full.

        The server runs on Cloudflare's free plan, which supports about 40 phones. Cloudflare's Workers Paid plan would cover the whole school.

        Thank you!
        """
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = contact
        parts.queryItems = [URLQueryItem(name: "subject", value: subject),
                            URLQueryItem(name: "body", value: body)]
        return parts.url
    }
}
