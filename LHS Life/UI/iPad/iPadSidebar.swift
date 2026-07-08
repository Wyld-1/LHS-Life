//
//  iPadSidebar.swift
//  LHS Life
//
//  Three zones, top to bottom:
//    Today   — the schedule pill, given real permanent space instead of
//               fighting for room in a header capsule.
//    Navigate — the four destinations, Reminders-sidebar style. Icons are
//               monochrome, tinted blue only when selected — matching the
//               iPhone tab dock's exact convention (LegacyDockButton),
//               not a per-row rainbow.
//    (pinned) Settings — lower-left, always visible when the sidebar is
//               expanded, same background as the rest of the sidebar (no
//               extra material layer) with a plain Divider above it.
//
//  Color note: this file uses SwiftUI's adaptive .primary/.secondary, NOT
//  the app's Color.lsPrimary/lsSecondary. Those two are hardcoded absolutes
//  (Color.white and a fixed gray) tuned for the app's permanently-dark
//  canvas elsewhere. The sidebar is genuine native List/sidebar chrome that
//  follows system light/dark mode on its own — pairing it with the
//  hardcoded-dark palette makes text unreadable in light mode.
//

import SwiftUI

struct iPadSidebar: View {

    @Binding var selectedTab: AppTab
    var onSameTabTap: (AppTab) -> Void = { _ in }
    let onSettingsTap: () -> Void
    let showSettingsBadge: Bool

    /// Same reselect-detection trick as the iPhone tab bar: the setter
    /// fires even when tapping the already-selected row, so we can treat
    /// that as "reload / go to today" the same way iPhone does.
    private var selection: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard let newValue else { return }
                if newValue == selectedTab {
                    onSameTabTap(newValue)
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ScheduleHeaderPill()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(AppTab.dockTabs, id: \.self) { tab in
                    NavRow(tab: tab, isSelected: tab == selectedTab).tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LHS Life")
        .safeAreaInset(edge: .bottom) {
            SettingsRow(onTap: onSettingsTap, showBadge: showSettingsBadge)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Nav Row

private struct NavRow: View {
    let tab: AppTab
    let isSelected: Bool

    private var tintColor: Color { isSelected ? Color.lsBlue : Color.secondary }

    var body: some View {
        Label {
            Text(tab.title)
                .font(.lsHeadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        } icon: {
            if tab.isCustomAsset {
                Image(tab.iconName)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(tintColor)
            } else {
                Image(systemName: tab.iconName)
                    .foregroundStyle(tintColor)
            }
        }
    }
}

// MARK: - Settings Row (pinned bottom)

private struct SettingsRow: View {
    let onTap: () -> Void
    let showBadge: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.secondary)
                        if showBadge {
                            Circle()
                                .fill(Color.lsDestructive)
                                .frame(width: 8, height: 8)
                                .offset(x: 5, y: -3)
                        }
                    }
                    Text("Settings")
                        .font(.lsHeadline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                }
                .padding(.horizontal, LS.lg)
                .padding(.vertical, LS.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
