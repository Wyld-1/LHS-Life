//
//  LHS_WidgetsLiveActivity.swift
//  LHS Widgets
//
//  UI matches LHS Life design: lightning logo, rounded fonts, dark background.
//  ContentState fields match the working LHS Live schema:
//    currentPeriodName, secondsRemaining, periodDurationSeconds,
//    nextPeriodName, nextBellTime, isOffSchedule, headerText
//  Progress computed from integer seconds — no Dates needed.
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
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image("lhs-lightning")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(Color(hex: context.attributes.periodColorHex))
                            .frame(width: 14, height: 14)
                        Text(context.state.currentPeriodName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

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

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let next = context.state.nextPeriodName {
                            HStack {
                                Text("Next: \(next)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        ProgressBar(progress: context.state.progress, color: Color(hex: context.attributes.periodColorHex))
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }

            } compactLeading: {
                Image("lhs-lightning")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(hex: context.attributes.periodColorHex))
                    .frame(width: 15, height: 15)
                    .padding(.leading, 2)

            } compactTrailing: {
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

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        let color = Color(hex: attributes.periodColorHex)
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image("lhs-lightning")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(color)
                        .frame(width: 18, height: 18)
                    Text(state.currentPeriodName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

            ProgressBar(progress: state.progress, color: color, height: 8)

            if let next = state.nextPeriodName {
                HStack {
                    Text("Next: \(next)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(hex: "#0D1220"))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Progress Bar
// Driven by progress computed from integer seconds in ContentState.

private struct ProgressBar: View {
    let progress: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: height)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * progress, height: height)
            }
        }
        .frame(height: height)
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
              secondsRemaining: 1800,
              periodDurationSeconds: 3000,
              nextPeriodName: "Lunch",
              nextBellTime: "11:45 AM",
              isOffSchedule: false,
              headerText: "30 min left in Chemistry")
    }
}

#Preview("In Class", as: .content, using: ScheduleActivityAttributes.preview) {
    LaSalle_WidgetsLiveActivity()
} contentStates: {
    ScheduleActivityAttributes.ContentState.inClass
}
