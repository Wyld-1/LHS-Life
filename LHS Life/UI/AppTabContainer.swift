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
    @State private var showCapacityAlert = false
    /// Observed so the capacity refusal below can reach the UI; the
    /// service is @Observable and a singleton, so this is a reference to
    /// the same instance LiveActivityService.shared hands everyone else.
    @State private var liveActivity = LiveActivityService.shared
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

    /// Spelled out rather than terse: this is the one failure in the app the
    /// student can actually act on, and the ask ("please upgrade the server")
    /// makes no sense without saying what is full and what still works.
    private var capacityMessage: String {
        let contact = liveActivity.capacityBlock?.contact ?? "the school office"
        return """
        Live Activities couldn't be started because the school's server is at capacity.

        Everything else works normally. This only affects the live bell schedule on your Lock Screen.

        If you'd like Live Activities, email \(contact) and ask for a server upgrade.
        """
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

    var body: some View {
        Group {
            if isPhone { iPhoneLayout } else { iPadLayout }
        }
        .overlay { EasterEggOverlay() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: calendarUI.appDidBackground()
            case .active:     calendarUI.appDidForeground()
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
        // The school's worker refused this device because it is full.
        .onChange(of: liveActivity.capacityBlock) { _, block in
            guard block != nil else { return }
            // Once a day at most. The student cannot fix this themselves —
            // it is someone else's budget decision — so repeating it every
            // launch would be nagging them about it.
            let today = DateFormatter.isoDay.string(from: Date())
            let key = "lhs_capacity_notice_day"
            guard UserDefaults.standard.string(forKey: key) != today else { return }
            UserDefaults.standard.set(today, forKey: key)
            showCapacityAlert = true
        }
        .alert("Live Activities Are Full", isPresented: $showCapacityAlert) {
            if let contact = liveActivity.capacityBlock?.contact,
               let url = URL(string: "mailto:\(contact)?subject=LHS%20Life%20server%20upgrade&body=Hello%2C%0A%0AI%20would%20like%20to%20use%20Live%20Activities%20in%20LHS%20Life%2C%20but%20the%20app%20says%20the%20school%27s%20server%20is%20full.%20Could%20the%20server%20be%20upgraded%3F%0A%0AThank%20you%21") {
                Link("Ask for an Upgrade", destination: url)
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(capacityMessage)
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
