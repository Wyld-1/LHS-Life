//
//  AppTabContainer.swift
//  LHS Life
//
//  Single branch point at the top level: iPhone vs iPad.
//
//  iPhone — PhoneLayout (UI/iPhone/): ZStack, floating header + tab dock.
//  iPad   — iPadRootView (UI/iPad/): NavigationSplitView, sidebar +
//           detail pane with a top-toolbar contextual button and a
//           persistent Homework FAB.
//

import SwiftUI
import StoreKit   // requestReview
internal import WebKit

// MARK: - Tab Definition

enum AppTab: Int, CaseIterable {
    case events      = 0
    case lunch       = 1
    case powerschool = 2
    case schoology   = 3
    case homework    = 4
    case map         = 5

    var title: String {
        switch self {
        case .events:       return "Events"
        case .lunch:        return "Order"
        case .powerschool:  return "Grades"
        case .schoology:    return "Schoology"
        case .homework:     return "Homework"
        case .map:          return "Map"
        }
    }

    /// SF Symbol name (or asset name when isCustomAsset).
    ///
    /// SINGLE SOURCE OF TRUTH. Every surface — the iOS 26 TabView, the legacy
    /// dock, and the iPad sidebar — reads this. SystemTabDock used to hardcode
    /// its own strings in the Tab(...) declarations, so editing this had no
    /// effect on iOS 26 and editing those had no effect anywhere else.
    ///
    /// Names are the FILLED variants deliberately. iOS tab bars substitute the
    /// .fill variant for any symbol they contain, and .symbolVariant(.none)
    /// does not reliably override that on the iOS 26 TabView — tried and
    /// reverted. Naming the filled variant outright means the string matches
    /// what actually renders, instead of lying about it.
    var iconName: String {
        switch self {
        case .events:       return "calendar"
        case .lunch:        return "fork.knife"
        case .powerschool:  return "powerschool-logo"
        case .schoology:    return "schoology-logo"
        case .homework:     return "checklist"
        case .map:          return "map.fill"
        }
    }

    var isCustomAsset: Bool {
        switch self {
        case .powerschool, .schoology: return true
        default: return false
        }
    }

    static var dockTabs: [AppTab] { [.events, .lunch, .powerschool, .schoology] }

    /// Legacy (pre-iOS 26) iPhone dock destinations. Overload rather than a
    /// replacement for `dockTabs` so nothing else that reads the plain array
    /// has to change. Map sits directly after Events, matching both the iOS
    /// 26 Tab order in PhoneTabDock and `sidebarTabs` below.
    static func dockTabs(showMap: Bool) -> [AppTab] {
        showMap ? [.events, .map, .lunch, .powerschool, .schoology]
                : [.events, .lunch, .powerschool, .schoology]
    }

    /// iPad sidebar destinations. Map sits directly after Events, mirroring
    /// where it appears in the iPhone tab bar. Kept separate from dockTabs
    /// because that array also drives the pre-26 iPhone dock, which has no
    /// Map content mounted.
    static var sidebarTabs: [AppTab] { [.events, .map, .lunch, .powerschool, .schoology] }
}

// MARK: - Root Container

struct AppTabContainer: View {

    @Environment(CalendarStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTab  = AppTab.events
    @State private var previousTab  = AppTab.events
    @State private var showSettings = false
    @State private var showHomework = false
    @State private var showContacts = false
    @State private var isLaunching  = true
    /// Hard ceiling on how long the launch screen can hold the app hostage.
    @State private var launchDeadlinePassed = false
    /// Gates whether the launch screen is EVER shown.
    ///
    /// A launch that finishes inside this window shows nothing but the
    /// system's own static launch image, then the app — no fade in, no fade
    /// out, no flash. Only a genuinely slow launch gets the SwiftUI screen,
    /// which is the only case it was ever useful in.
    ///
    /// Deliberately NOT a minimum display time: padding every launch to fix
    /// the appearance of a fast one makes the app worse for everyone, and a
    /// slow launch is more noticeable than a brief flash.
    @State private var launchScreenDue = false
    /// The once-a-season "pick your icon" card (AppIconIntroCard).
    @State private var showIconIntro = false
    @State private var calendarUI   = CalendarUIState()
    @State private var navCoordinator = AppNavigationCoordinator.shared

    @State private var lunchState = EmbeddedWebState(
        url: URL(string: "https://lhs.plan.tech/lunch/")!,
        siteName: "Lunch Order",
        injectDarkCSS: true
    )
    @State private var powerschoolState = EmbeddedWebState(
        url: URL(string: "https://lasalleyakima.powerschool.com/guardian/home.html?_userTypeHint=student#")!,
        siteName: "PowerSchool"
    )
    @State private var schoologyState = EmbeddedWebState(
        url: URL(string: "https://lasalleyakima.schoology.com/home")!,
        siteName: "Schoology"
    )

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Launch gate — the CALENDAR only.
    ///
    /// This used to require all three web views to report isReady, so the
    /// launch screen sat there until PowerSchool and Schoology had finished
    /// loading — two tabs most launches never open. The web views were
    /// already loading concurrently in the background (see .task below);
    /// waiting on them bought nothing except a slower launch.
    ///
    /// They keep loading exactly as before, off the main thread. A tab opened
    /// before its page is ready shows that tab's own first-load spinner,
    /// which is the honest place for it — the cost lands on whoever actually
    /// asked for that tab, instead of on everyone.
    ///
    /// launchDeadlinePassed is a safety net: store.events being empty is not
    /// a reliable "still loading" signal, since a student with genuinely no
    /// events would otherwise never get past the launch screen at all.
    private var launchProgress: Double {
        (!store.events.isEmpty || launchDeadlinePassed) ? 1.0 : 0.0
    }

    /// Drops the launch screen once the gate is satisfied. Safe to call as
    /// often as you like; it does nothing after the first time.
    ///
    /// Deliberately NOT wrapped in withAnimation. That opens an animated
    /// transaction around the whole state write, so every geometry change
    /// resulting from it gets animated from old to new — which is what made
    /// the UI appear to fly in from the edges on both iPhone and iPad. The
    /// fade lives on LaunchScreen's own transition, which is the only thing
    /// that should animate.
    private func resolveLaunchIfReady() {
        guard isLaunching, launchProgress >= 1.0 else { return }
        isLaunching = false
    }

    /// Asks iOS for a rating prompt, if this is a good moment.
    ///
    /// ReviewPrompter decides whether the person's history makes it OK to
    /// ask; this decides whether the screen does. The pause lets the app
    /// settle and the person get their bearings, and the re-check after it
    /// catches them opening something in the meantime — a prompt on top of
    /// Settings or the homework sheet is exactly the interruption Apple's
    /// guidance warns against.
    private func considerReviewPrompt() {
        ReviewPrompter.recordActiveDay()
        guard ReviewPrompter.isGoodTimeToAsk else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard scenePhase == .active, !isLaunching, selectedTab == .events,
                  !showSettings, !showHomework, !showContacts, !showIconIntro,
                  ReviewPrompter.isGoodTimeToAsk
            else { return }
            ReviewPrompter.markAsked()
            requestReview()
        }
    }

    /// Slides up the seasonal icon card, once per season, after launch has
    /// settled and nothing else is on screen.
    private func considerIconIntro() {
        guard AppIconService.shared.shouldIntroduce, !showIconIntro else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard scenePhase == .active, !isLaunching,
                  !showSettings, !showHomework, !showContacts,
                  AppIconService.shared.shouldIntroduce
            else { return }
            showIconIntro = true
        }
    }

    var body: some View {
        Group {
            if isPhone { iPhoneLayout } else { iPadLayout }
        }
        .overlay { EasterEggOverlay() }
        .modifier(AppIconIntroOverlay(isPresented: $showIconIntro))
        #if DEBUG
        // Under -demoClock the system clock can't follow the fake one — the
        // simulator's status-bar override is frozen and misreads the year —
        // so the status bar is hidden rather than shown disagreeing.
        .statusBarHidden(DebugClock.shared.offset != 0)
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: calendarUI.appDidBackground()
            case .active:
                calendarUI.appDidForeground()
                considerIconIntro()
                considerReviewPrompt()
            default:          break
            }
        }
        .onChange(of: launchProgress) { _, _ in resolveLaunchIfReady() }
        .onChange(of: selectedTab) { _, new in
            if new == .homework {
                selectedTab = previousTab
                withAnimation(.lsSpring) { showHomework = true }
            } else {
                previousTab = new
            }
        }
        .onChange(of: navCoordinator.pendingTab) { _, target in
            guard let target else { return }
            if target == .homework {
                withAnimation(.lsSpring) { showHomework = true }
            } else {
                selectedTab = target
            }
            navCoordinator.pendingTab = nil
        }
        #if DEBUG
        .task {
            // Under -demoClock, open on the fake day rather than the real one.
            if DebugClock.shared.offset != 0 {
                calendarUI.selectedDate = Calendar.current.startOfDay(for: DebugClock.shared.now)
                calendarUI.scrollIntent = .now
            }
        }
        #endif
        .task {
            // Fire-and-forget. These three load concurrently in the
            // background and nothing waits on them — the app is interactive
            // as soon as the calendar is ready, and each tab reports its own
            // readiness when opened.
            async let l: () = lunchState.initialize()
            async let p: () = powerschoolState.initialize()
            async let s: () = schoologyState.initialize()
            _ = await (l, p, s)
        }
        .task {
            // Catches the case onChange structurally cannot: a launch that is
            // ALREADY finished when this view is created.
            //
            // onChange only fires on a change. When a student signs in while
            // the app is running — the second sign-in after Delete All Data or
            // Sign Out — CalendarStore is a singleton that still holds the
            // events it loaded the first time, so launchProgress is 1.0 from
            // the very first render of this view. Nothing ever changed, so
            // nothing ever cleared isLaunching, and the launch screen sat
            // there until the app was force-quit. That is the whole bug: the
            // gate was watching for an edge that had already passed.
            resolveLaunchIfReady()
        }
        .task {
            // Safety net — see launchProgress. Never let the launch screen
            // outlive this, regardless of what the calendar is doing.
            try? await Task.sleep(for: .seconds(2.5))
            launchDeadlinePassed = true
            // Explicit, not implied: if launchProgress was already 1.0 the
            // line above changes nothing, and the onChange above would not
            // fire. This is the unconditional backstop.
            resolveLaunchIfReady()
            // A cold launch arrives already active, so the scenePhase
            // onChange above never fires for it. Once launch is settled is
            // the right moment anyway.
            considerIconIntro()
            considerReviewPrompt()
        }
        .task {
            // Delay-then-show. If loading beats this, isLaunching is already
            // false and the screen never appears at all.
            try? await Task.sleep(for: .milliseconds(300))
            launchScreenDue = true
        }
        .background {
            SettingsSheetView(settings: settings)
                .frame(width: 0, height: 0).opacity(0)
                .allowsHitTesting(false).clipped()
            ColorPickerPrewarm()
                .frame(width: 0, height: 0).opacity(0)
                .allowsHitTesting(false).clipped()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(settings: settings)
                // Environment is re-injected explicitly rather than inherited.
                // On iOS a sheet inherits the presenting view's environment,
                // which is why this worked on iPhone and iPad. On macOS the
                // sheet is hosted outside that chain, the inheritance breaks,
                // and SettingsSheetView's @Environment(CalendarStore.self)
                // traps with "No Observable object of type CalendarStore
                // found."
                //
                // Same reason iPadRootView already re-injects store/settings
                // into HomeworkPopup — this sheet just never got the same
                // treatment.
                .environment(store)
                .environment(settings)
                .environment(calendarUI)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.lsSurface)
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        PhoneLayout(
            selectedTab: $selectedTab,
            showSettings: $showSettings,
            showHomework: $showHomework,
            showContacts: $showContacts,
            isLaunching: isLaunching && launchScreenDue,
            launchProgress: launchProgress,
            calendarUI: calendarUI,
            lunchState: lunchState,
            powerschoolState: powerschoolState,
            schoologyState: schoologyState
        )
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        iPadRootView(
            selectedTab: $selectedTab,
            showSettings: $showSettings,
            showHomework: $showHomework,
            isLaunching: isLaunching && launchScreenDue,
            launchProgress: launchProgress,
            calendarUI: calendarUI,
            lunchState: lunchState,
            powerschoolState: powerschoolState,
            schoologyState: schoologyState
        )
    }

}

#Preview {
    AppTabContainer()
        .environment(CalendarStore())
        .environment(UserSettings.shared)
}
