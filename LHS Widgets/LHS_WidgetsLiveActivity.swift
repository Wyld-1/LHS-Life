//
//  LHS_WidgetsLiveActivity.swift
//  LHS Widgets
//
//  Dynamic Island:
//    Compact leading  — lhs-lightning logo in period color
//    Compact trailing — bell icon + next bell time
//    Minimal          — circular progress arc
//    Expanded         — period name, bell + time, progress bar, next period
//
//  Lock screen banner — period name, bell + next bell time, thick progress
//                       bar, next period line. Mirrors the app header.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LaSalle_WidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {

                // MARK: Expanded — leading: period color + period name
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .foregroundStyle(Color(hex: context.attributes.periodColorHex))
                            .frame(width: 12, height: 12)
                        Text(context.state.currentPeriodName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                // MARK: Expanded — trailing: bell + next bell time
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        if let bellTime = context.state.nextBellTime {
                            Text(bellTime)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.trailing, 4)
                }

                // MARK: Expanded — bottom: next period + progress bar
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let next = context.state.nextPeriodName {
                            HStack {
                                Text("Next: \(next)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        
                        Spacer()
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.15))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(Color(hex: context.attributes.periodColorHex))
                                    .frame(width: geo.size.width * context.state.progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }

            } compactLeading: {
                // LaSalle lightning logo in period color
                Image("lhs-lightning")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(hex: context.attributes.periodColorHex))
                    .frame(width: 15, height: 15)
                    .padding(.leading, 2)

            } compactTrailing: {
                // Bell + next bell time
                HStack(spacing: 3) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    if let bellTime = context.state.nextBellTime {
                        Text(bellTime)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.trailing, 2)

            } minimal: {
                // Circular progress arc with logo inside
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(Color(hex: context.attributes.periodColorHex), lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color(hex: context.attributes.periodColorHex))
                        .frame(width: 8, height: 8)
                }
                .padding(2)
            }
            .keylineTint(Color(hex: context.attributes.periodColorHex))
        }
    }
}

// MARK: - Lock Screen / Banner View
// Mirrors the app header: period, bell time, progress, next period.

private struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {

            // Top row: logo + period name | bell + time
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color(hex: attributes.periodColorHex))
                        .frame(width: 18, height: 18)
                    Text(state.currentPeriodName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                if let bellTime = state.nextBellTime {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(bellTime)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }

            // Progress bar — thicker than Dynamic Island version
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(Color(hex: attributes.periodColorHex))
                        .frame(width: geo.size.width * state.progress, height: 8)
                }
            }
            .frame(height: 8)

            // Next period
            if let next = state.nextPeriodName {
                HStack {
                    Text("Next: \(next)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(hex: "#0D1220"))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

extension ScheduleActivityAttributes {
    fileprivate static var preview: ScheduleActivityAttributes {
        ScheduleActivityAttributes(periodColorHex: "#3A6FD8", schoolName: "LaSalle")
    }
}

extension ScheduleActivityAttributes.ContentState {
    fileprivate static var inClass: ScheduleActivityAttributes.ContentState {
        .init(currentPeriodName: "Chemistry",
              secondsRemaining: 1847,
              periodDurationSeconds: 3000,
              nextPeriodName: "Lunch",
              nextBellTime: "10:50 AM",
              isOffSchedule: false,
              headerText: "30m left in Chemistry")
    }
}

#Preview("Notification", as: .content, using: ScheduleActivityAttributes.preview) {
    LaSalle_WidgetsLiveActivity()
} contentStates: {
    ScheduleActivityAttributes.ContentState.inClass
}
