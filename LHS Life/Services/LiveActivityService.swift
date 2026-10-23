//
//  LiveActivityService.swift
//  LHS Life
//
//  Starts and ends the schedule Live Activity.
//
//  Cards subscribe to the school's broadcast channel
//  (AppConstants.broadcastChannel). The Cloudflare Worker sends one push per
//  bell to that channel and each card works out its own class from the
//  schedule it carries, so all the worker needs from a phone is its bell
//  times (BellReporter) — no token, no device ID.
//
//  currentActivity is in-memory only — lost on app suspend/resume.
//  reconnect() restores it from ActivityKit's live activities list on launch.
//

import Foundation
import ActivityKit
import UserNotifications
import OSLog
import UIKit

@MainActor
@Observable
final class LiveActivityService {

    static let shared = LiveActivityService()
    private init() {}

    private var currentActivity: Activity<ScheduleActivityAttributes>?
    /// Sleeps until the running card's last bell, then ends it if the day is
    /// over. See scheduleEndCheck(at:).
    private var endCheckTask: Task<Void, Never>?
    private(set) var isDebugSession = false

    // MARK: - Reconnect (call on app launch/foreground)
    // Restores currentActivity from ActivityKit if the app was suspended.

    /// True when a Live Activity is currently running.
    var isRunning: Bool { currentActivity != nil }

    /// Set when the user taps the "Start Live Activities" notification
    /// action. Consumed on the next foreground so the confirmation overlay
    /// appears once the app is actually on screen — the action itself may
    /// fire while the app is backgrounded, where an overlay would be lost.
    var pendingStartConfirmation = false

    /// Why the last startIfNeeded call declined to start, phrased for the
    /// user rather than the log. nil after a successful start (or when one
    /// was already running).
    ///
    /// Separate from the LHSLogger lines on purpose: those name internal
    /// state ("liveActivityEffectivelyEnabled false (mode: .off…)") and are
    /// for us. These are for a sophomore reading a card on their phone.
    private(set) var lastStartFailure: String?

    /// Observes the running activity so we can tell, from the DEVICE side,
    /// whether pushes are arriving at all.
    ///
    /// This is the missing half of the diagnosis: worker logs prove APNs
    /// accepted a push, but only contentUpdates proves iOS delivered it and
    /// ActivityKit applied it. If the worker says 200 and this logs nothing,
    /// the failure is between APNs and the device (budget throttling, a
    /// channel from the wrong APNs environment). If this logs an update and the Lock Screen still shows the old
    /// period, the failure is in the widget's rendering — two very different
    /// problems that look identical from the outside.
    private func observeActivity(_ activity: Activity<ScheduleActivityAttributes>) {
        Task { @MainActor in
            for await content in activity.contentUpdates {
                LHSLogger.liveActivity.notice(
                    "contentUpdate received — slotStartMinutes: \(content.state.slotStartMinutes), isEnded: \(content.state.isEnded)"
                )
            }
            LHSLogger.liveActivity.notice("contentUpdates stream ended")
        }

        Task { @MainActor in
            for await state in activity.activityStateUpdates {
                LHSLogger.liveActivity.notice("activityState → \(String(describing: state), privacy: .public)")
            }
        }
    }

    func reconnect() {
        guard currentActivity == nil else { return }
        // Only an activity that is still on screen. ActivityKit keeps ended
        // and dismissed activities in this list for a while afterwards, and
        // adopting one of those made startIfNeeded bail with "already running"
        // while nothing was actually running — the reason a Live Activity
        // ended from the debug menu could not be restarted without a relaunch.
        adoptPreview()
        currentActivity = ScheduleActivityAttributes.realActivities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
        if let a = currentActivity {
            LHSLogger.liveActivity.notice("Reconnected to existing activity — id: \(a.id, privacy: .public)")
            // Reconnecting after a relaunch must re-observe, or a warm-start
            // day produces no device-side evidence at all.
            observeActivity(a)

            // Re-report the card's bells on reconnect. One small request per
            // relaunch, and the worker merges repeats — but it heals a worker
            // that lost today's list (a redeploy, a wiped store), which would
            // otherwise leave this card without pushes for the rest of the day.
            // attributes.schedule is the schedule the card was started with,
            // so the bells sent are the ones the card will act on.
            if let lastBell = a.attributes.schedule.last?.endDate {
                if lastBell > Date() { BellReporter.report(a.attributes.schedule) }
                scheduleEndCheck(at: lastBell)
            }
        }
    }

    // MARK: - Start if needed

    /// Whether ActivityKit will accept a start request right now.
    private var isAppInForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    func startIfNeeded(schedule: BellSchedule?, settings: UserSettings) {
        reconnect()
        if let running = currentActivity {
            // A Live Activity's schedule is fixed when it is created and can
            // never be edited afterwards. So if today's schedule changed after
            // this one started — an image-posted day that finished reading,
            // an event edited in CalendarWiz, a class turned on or off — the
            // only correction is to replace it. Otherwise it carries the wrong
            // bells for the rest of the day, and the worker never hears the
            // new ones. The replacement reports them when it starts.
            if !isDebugSession, let schedule, scheduleHasChanged(since: running, to: schedule, settings: settings) {
                // Checked BEFORE ending the old card, not just before starting
                // the new one. Ending works from the background; starting
                // doesn't. Replacing from the background would take the card
                // off the Lock Screen and fail to put one back. The next
                // foreground runs this again.
                guard isAppInForeground else {
                    LHSLogger.liveActivity.notice("Schedule changed, but app is in the background — replacing on next foreground")
                    return
                }
                LHSLogger.liveActivity.notice(
                    "Schedule changed since this Live Activity started — replacing \(running.id, privacy: .public)"
                )
                Task { @MainActor in
                    await end()
                    startIfNeeded(schedule: schedule, settings: settings)
                }
                return
            }
            LHSLogger.liveActivity.notice("bail: activity already running (id: \(running.id, privacy: .public))")
            // Already running is a success from the user's point of view —
            // they asked for a Live Activity and there is one.
            lastStartFailure = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LHSLogger.liveActivity.error("bail: activities not enabled in system settings")
            lastStartFailure = "Turn on Live Activities in iPhone Settings"
            return
        }
        let scheduleType = schedule?.scheduleType
        guard settings.liveActivityEffectivelyEnabled(scheduleType: scheduleType) else {
            LHSLogger.liveActivity.error(
                "bail: liveActivityEffectivelyEnabled false (mode: \(String(describing: settings.liveActivityMode), privacy: .public), type: \(String(describing: scheduleType), privacy: .public))"
            )
            lastStartFailure = "Live Activities are turned off in LHS Life settings"
            return
        }
        // Broadcast channels need iOS 18, and so does the widget extension
        // that draws the card — on iOS 17 there would be nothing to show.
        guard #available(iOS 18, *) else {
            LHSLogger.liveActivity.notice("bail: iOS 17 — broadcast Live Activities need iOS 18")
            lastStartFailure = "Needs iOS 18"
            return
        }
        guard let schedule = schedule else {
            LHSLogger.liveActivity.error("bail: schedule is nil")
            lastStartFailure = "No bell schedule for today"
            return
        }
        // Never start on a day endIfSchoolOver would end. If the two ever
        // disagree, the card is started and ended in a loop — which is what a
        // misread "holiday" did on Oct 15: a card that kept vanishing.
        switch CalendarStore.shared.todayState(at: Date()).dayState {
        case .afterSchool, .holiday, .pathwaysDay:
            LHSLogger.liveActivity.notice("bail: no school left today for this student")
            lastStartFailure = "No school today"
            return
        default:
            break
        }
        // The whole day for the worker, what's left of it for the card.
        // Reporting only the remaining bells made every phone that started
        // at a different time look like a different schedule (seven of them
        // on Oct 22 2026), and could run the worker into its 30-a-day cap.
        let fullDay = buildSchedule(from: schedule, settings: settings, upcomingOnly: false)
        let periods = fullDay.filter { $0.endDate > Date() }
        guard !periods.isEmpty else {
            LHSLogger.liveActivity.error("bail: periods empty after buildSchedule")
            lastStartFailure = "No classes enabled in your schedule"
            return
        }
        if let firstBell = periods.first?.startDate, firstBell.timeIntervalSinceNow > 3600 {
            LHSLogger.liveActivity.notice("bail: first bell too far away (\(Int(firstBell.timeIntervalSinceNow / 60))min)")
            lastStartFailure = "School hasn't started yet today"
            return
        }

        // ActivityKit only starts a Live Activity for an app that's in front;
        // from the background it throws ActivityAuthorizationError.visibility.
        // That happened in production: this runs after the calendar finishes
        // loading, a few seconds after launch — long enough for a student to
        // have already left, or for iOS to have launched the app in the
        // background. Not a failure to show anyone: the scenePhase .active
        // handler calls this again the next time the app comes forward.
        guard isAppInForeground else {
            LHSLogger.liveActivity.notice("bail: app not in foreground — will start on next foreground")
            return
        }

        CachedSchedule.save(periods)

        let cal      = Calendar.current
        let firstSlot = periods.first(where: { Date() >= $0.startDate && Date() < $0.endDate })
                     ?? periods.first(where: { $0.startDate > Date() })
        let h = firstSlot.map { cal.component(.hour,   from: $0.startDate) } ?? 0
        let m = firstSlot.map { cal.component(.minute, from: $0.startDate) } ?? 0
        let state    = ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m,
            isEnded: false
        )
        let lastBell = periods.last?.endDate ?? Date().addingTimeInterval(3600)

        let attributes = ScheduleActivityAttributes(
            schoolName: "LaSalle",
            scheduleTypeName: schedule.scheduleType.scheduleLabel,
            schedule: periods
        )

        // The real thing replaces the preview; two cards would be confusing.
        if previewActivity != nil {
            Task { await endPreview() }
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content:    .init(state: state, staleDate: lastBell),
                pushType:   .channel(AppConstants.broadcastChannel)
            )
            currentActivity = activity
            lastStartFailure = nil
            LHSLogger.liveActivity.notice("Started — id: \(activity.id, privacy: .public), \(periods.count) periods")
            observeActivity(activity)

            // The worker only broadcasts at bells someone has reported, so a
            // card whose bells it hasn't heard would sit still all day.
            BellReporter.report(fullDay)

            // Cancel the "school starts soon" reminder — LA is already running
            let todayKey = DateFormatter.isoDay.string(from: Date())
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["lareminder-\(todayKey)"]
            )

            let upcoming = periods.filter { $0.startDate > Date() }
            BellTransitionService.scheduleTransitions(for: upcoming)
            scheduleEndCheck(at: lastBell)
        } catch {
            // The likeliest TestFlight-only failure: a broadcast channel needs
            // the push entitlement, and an App Store provisioning profile
            // generated before Push Notifications was enabled on the App ID
            // won't carry it. Logged at .error so it survives to Console.app.
            LHSLogger.liveActivity.error("Failed to start: \(String(describing: error), privacy: .public)")
            IssueReporter.report(.liveActivityStart, detail: String(describing: error))
            lastStartFailure = "Couldn't start Live Activities"
        }
    }

    // MARK: - Dummy start (debug only)
    // Starts a fake 2-minute schedule anchored to now, immune to school-over checks.
    //
    // pushType nil: not on the broadcast channel, so it can't collide with a
    // real card (one channel subscription per device) and never hears the
    // worker. Only the on-device BellTransitionService moves it.

    func startDummy() {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let p1End   = now.addingTimeInterval(120)
        let passEnd = now.addingTimeInterval(150)
        let p2End   = now.addingTimeInterval(270)
        let periods: [ScheduleActivityAttributes.ScheduledPeriod] = [
            .init(periodNumber: 1,   displayName: "English",
                  colorHex: "#FF6B6B",
                  startDate: now.addingTimeInterval(-5), endDate: p1End,
                  endTimeString: fmt.string(from: p1End)),
            .init(periodNumber: nil, displayName: "Passing",
                  colorHex: "#94A3B8",
                  startDate: p1End, endDate: passEnd,
                  endTimeString: fmt.string(from: passEnd)),
            .init(periodNumber: 2,   displayName: "Chemistry",
                  colorHex: "#F5B800",
                  startDate: passEnd, endDate: p2End,
                  endTimeString: fmt.string(from: p2End)),
        ]
        let cal = Calendar.current
        let h   = cal.component(.hour,   from: periods[0].startDate)
        let m   = cal.component(.minute, from: periods[0].startDate)
        let state = ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m, isEnded: false
        )
        CachedSchedule.save(periods)
        do {
            let activity = try Activity.request(
                attributes: ScheduleActivityAttributes(
                    schoolName: "LaSalle",
                    scheduleTypeName: "Debug Schedule",
                    schedule: periods
                ),
                content: .init(state: state, staleDate: now.addingTimeInterval(6000)),
                pushType: nil
            )
            currentActivity = activity
            isDebugSession  = true
            print("[LiveActivity] Dummy started — id: \(activity.id)")
            BellTransitionService.scheduleTransitions(for: periods.filter { $0.startDate > now })
        } catch {
            print("[LiveActivity] Dummy start failed: \(error)")
        }
    }

    #if DEBUG
    // MARK: - Screenshot demo (debug only)
    //
    // A believable mid-class card for App Store and marketing screenshots:
    // a full Regular day with real class names, 27 minutes into Chemistry.
    //
    // The card's time LABELS are staged at `stagedNow` (10:27 AM) so they
    // agree with a simulator whose clock is overridden to match:
    //     xcrun simctl status_bar <device> override --time 2026-09-29T10:27:00-07:00
    // while the real dates keep the same distances from the real now, so
    // the progress bar sits at the right point in the class.
    //
    // pushType nil: off the broadcast channel, so worker pushes can't move
    // it away from the staged moment.
    func startScreenshotDemo(stagedHour: Int = 10, stagedMinute: Int = 27) {
        let realNow = Date()
        let cal = Calendar.current
        guard let stagedNow = cal.date(bySettingHour: stagedHour, minute: stagedMinute, second: 0, of: realNow)
        else { return }
        let offset = realNow.timeIntervalSince(stagedNow)
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"

        func slot(_ number: Int?, _ name: String, _ hex: String,
                  _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int) -> ScheduleActivityAttributes.ScheduledPeriod {
            let start = cal.date(bySettingHour: sh, minute: sm, second: 0, of: stagedNow)!
            let end   = cal.date(bySettingHour: eh, minute: em, second: 0, of: stagedNow)!
            return .init(periodNumber: number, displayName: name, colorHex: hex,
                         startDate: start.addingTimeInterval(offset),
                         endDate: end.addingTimeInterval(offset),
                         endTimeString: fmt.string(from: end))
        }
        let periods = [
            slot(1,   "English",        "#FF6B6B",  8, 0,  8, 50),
            slot(2,   "Spanish II",     "#FB923C",  8, 55, 9, 45),
            slot(nil, "Break",          "#94A3B8",  9, 45, 9, 55),
            slot(3,   "Chemistry",      "#F5B800", 10, 0, 10, 50),
            slot(4,   "US History",     "#34C78A", 10, 55, 11, 45),
            slot(nil, "Lunch",          "#94A3B8", 11, 45, 12, 15),
            slot(5,   "Graphic Design", "#38BDF8", 12, 20, 13, 10),
            slot(6,   "Pre-Calculus",   "#3A6FD8", 13, 15, 14, 5),
            slot(7,   "Theology",       "#A78BFA", 14, 10, 15, 0),
        ]
        guard let current = periods.first(where: { realNow >= $0.startDate && realNow < $0.endDate }) else { return }
        let state = ScheduleActivityAttributes.ContentState(
            slotStartMinutes: cal.component(.hour, from: current.startDate) * 60
                            + cal.component(.minute, from: current.startDate),
            isEnded: false
        )

        Task { @MainActor in
            await end()
            do {
                currentActivity = try Activity.request(
                    attributes: ScheduleActivityAttributes(
                        schoolName: "LaSalle",
                        scheduleTypeName: "Regular Schedule",
                        schedule: periods
                    ),
                    content: .init(state: state, staleDate: periods.last?.endDate),
                    pushType: nil
                )
                isDebugSession = true
                LHSLogger.liveActivity.notice("Screenshot demo started")
            } catch {
                LHSLogger.liveActivity.error("Screenshot demo failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
    #endif

    // MARK: - End if school over

    /// Ends the card when the student's day is over: at their last bell if
    /// the app is open then, or on the next foreground (checkSchoolOver).
    ///
    /// The worker can't end one student's card at that student's last bell —
    /// a broadcast reaches every card — so from the last bell until this
    /// runs, the card shows "Done for today" (LHS_WidgetsLiveActivity).
    ///
    /// This used to ride on the header's once-a-second timer, which asked
    /// "is school over?" thousands of times a day. One wrong answer — an
    /// event misread as a holiday — then ended the card every second while
    /// the start logic put it back: the Oct 15 restart loop. Two checks a day
    /// can't loop.
    ///
    /// Task.sleep runs on the continuous clock, which keeps counting while the
    /// app is suspended, so a phone reopened after the last bell runs the
    /// check straight away.
    private func scheduleEndCheck(at lastBell: Date) {
        endCheckTask?.cancel()
        endCheckTask = Task { @MainActor [weak self] in
            let delay = lastBell.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.checkSchoolOver()
        }
    }

    /// The "is school over?" check against right now. Called on every
    /// foreground and by scheduleEndCheck.
    func checkSchoolOver() {
        endIfSchoolOver(state: CalendarStore.shared.todayState(at: DebugClock.shared.now))
    }

    func endIfSchoolOver(state: ScheduleEngine.ScheduleState) {
        guard !isDebugSession else { return }   // leave debug sessions alone
        switch state.dayState {
        case .afterSchool, .holiday, .pathwaysDay:
            guard currentActivity != nil ||
                  !ScheduleActivityAttributes.realActivities.isEmpty
            else { return }
            Task { await end() }
        default:
            break
        }
    }

    // MARK: - End

    func end() async {
        isDebugSession = false
        CachedSchedule.clear()
        // End all activities in case of duplicates from BGTask timing issues.
        // Not the preview: it has its own End button, and "school's over"
        // has nothing to do with it.
        for activity in ScheduleActivityAttributes.realActivities {
            await activity.end(.init(state: .init(isEnded: true), staleDate: nil),
                               dismissalPolicy: .immediate)
        }
        currentActivity = nil
        print("[LiveActivity] Ended all activities")
    }

    // MARK: - Preview

    /// The PREVIEW card — what a Live Activity looks like, for students who
    /// don't know the term. Started from Settings → Lock Screen.
    ///
    /// Entirely local: no broadcast channel, no server, no schedule. The
    /// widget draws it frozen from `attributes.preview` (see
    /// LHS_WidgetsLiveActivity), so it works at 9 PM on a Saturday.
    /// It ends from the app's End Preview button, a swipe on the Lock Screen,
    /// or a real Live Activity starting.
    private var previewActivity: Activity<ScheduleActivityAttributes>?
    private(set) var isPreviewRunning = false
    /// Why the last preview didn't start, phrased for the student.
    private(set) var previewFailure: String?

    func startPreview() {
        previewFailure = nil
        adoptPreview()
        guard previewActivity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            previewFailure = "Turn on Live Activities for LHS Life in the Settings app."
            return
        }
        // Never two: clear any preview that isn't this service's (one from
        // an earlier launch still starting up) before putting up a new one.
        for stray in Activity<ScheduleActivityAttributes>.activities where stray.attributes.preview != nil {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
        // A believable moment mid-class: 28 minutes into a 50-minute period.
        let minutesLeft = 22, length = 50
        let bell = Date().addingTimeInterval(TimeInterval(minutesLeft * 60))
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let preview = ScheduleActivityAttributes.Preview(
            className: "Chemistry",
            colorHex: "#F5B800",
            nextClassName: "US History",
            minutesLeft: minutesLeft,
            bellTime: fmt.string(from: bell),
            progress: Double(length - minutesLeft) / Double(length)
        )
        do {
            let activity = try Activity.request(
                attributes: ScheduleActivityAttributes(
                    schoolName: "LaSalle",
                    scheduleTypeName: "Regular Schedule",
                    schedule: [],
                    preview: preview
                ),
                content: .init(state: .init(), staleDate: nil),
                pushType: nil
            )
            previewActivity = activity
            isPreviewRunning = true
            observePreview(activity)
            LHSLogger.liveActivity.notice("Preview started — id: \(activity.id, privacy: .public)")
        } catch {
            previewFailure = "Couldn't start the preview. Try again."
            LHSLogger.liveActivity.error("Preview failed: \(String(describing: error), privacy: .public)")
        }
    }

    func endPreview() async {
        for activity in Activity<ScheduleActivityAttributes>.activities where activity.attributes.preview != nil {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        previewActivity = nil
        isPreviewRunning = false
    }

    /// Picks up a preview still on screen from an earlier launch, so the
    /// button reads End Preview instead of starting a second one.
    func adoptPreview() {
        guard previewActivity == nil,
              let activity = Activity<ScheduleActivityAttributes>.activities.first(where: {
                  // Anything not finished: on iOS 26 a just-requested card is
                  // .pending, not .active, for a moment.
                  $0.attributes.preview != nil
                      && $0.activityState != .ended && $0.activityState != .dismissed
              })
        else { return }
        previewActivity = activity
        isPreviewRunning = true
        observePreview(activity)
    }

    /// A swipe on the Lock Screen ends it without the app hearing about it
    /// any other way.
    private func observePreview(_ activity: Activity<ScheduleActivityAttributes>) {
        Task { @MainActor [weak self] in
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                guard let self, self.previewActivity?.id == activity.id else { return }
                self.previewActivity = nil
                self.isPreviewRunning = false
                return
            }
        }
    }

    // MARK: - Content state builder
    // Shared by startIfNeeded and updateNow — always computes from current time.

    func buildContentState(
        from periods: [ScheduleActivityAttributes.ScheduledPeriod]
    ) -> ScheduleActivityAttributes.ContentState? {
        let now = Date()
        let cal = Calendar.current

        // Find the active or next upcoming period
        let current = periods.first(where: { now >= $0.startDate && now < $0.endDate })
                   ?? periods.first(where: { $0.startDate > now })

        guard let current else { return nil }

        // slotStartMinutes identifies the slot — the widget matches it
        // against its own schedule, as it does a broadcast
        let h = cal.component(.hour,   from: current.startDate)
        let m = cal.component(.minute, from: current.startDate)
        return ScheduleActivityAttributes.ContentState(
            slotStartMinutes: h * 60 + m,
            isEnded: false
        )
    }

    // MARK: - Schedule Builder

    /// Whether the periods still ahead on a running card differ from what
    /// today's schedule would produce now.
    ///
    /// Only the periods that haven't ended are compared, on both sides.
    /// buildSchedule drops finished periods, so a card started at 8:00 and a
    /// rebuild at noon legitimately differ in length; comparing whole lists
    /// would replace the card every time the app opened. What matters is
    /// whether anything still to come is wrong.
    private func scheduleHasChanged(
        since activity: Activity<ScheduleActivityAttributes>,
        to schedule: BellSchedule,
        settings: UserSettings
    ) -> Bool {
        struct Slot: Equatable { let name: String; let start: Date; let end: Date }
        let now = Date()
        let running = activity.attributes.schedule
            .filter { $0.endDate > now }
            .map { Slot(name: $0.displayName, start: $0.startDate, end: $0.endDate) }
        let wanted = buildSchedule(from: schedule, settings: settings)
            .map { Slot(name: $0.displayName, start: $0.startDate, end: $0.endDate) }
        return running != wanted
    }

    func buildSchedule(
        from schedule: BellSchedule,
        settings: UserSettings,
        upcomingOnly: Bool = true
    ) -> [ScheduleActivityAttributes.ScheduledPeriod] {
        let mapped = schedule.periods.compactMap { period -> ScheduleActivityAttributes.ScheduledPeriod? in
            guard let start = period.startDate(on: schedule.date),
                  let end   = period.endDate(on: schedule.date)
            else { return nil }

            // Handle "Period 5 Final" — extract the number from the base name,
            // then re-attach " Final" to the user's configured class display name.
            let hasFinalSuffix = period.name.hasSuffix(" Final")
            let baseName = hasFinalSuffix
                ? String(period.name.dropLast(" Final".count))
                : period.name

            let num    = extractPeriodNumber(from: baseName)
            let config = num.flatMap { settings.config(for: $0) }

            // Skip periods the user has disabled.
            // Named slots without a period number (Senior Presentation, Break, Lunch)
            // are never disabled — they have no config.
            if let config, !config.isEnabled { return nil }

            let colorHex    = config.map { ColorPalette.color(at: $0.colorIndex).hex } ?? "#94A3B8"
            let baseDisplay = config?.displayName ?? baseName
            let displayName = hasFinalSuffix ? "\(baseDisplay) Final" : baseDisplay

            return ScheduleActivityAttributes.ScheduledPeriod(
                periodNumber:  num,
                displayName:   displayName,
                colorHex:      colorHex,
                startDate:     start,
                endDate:       end,
                endTimeString: ScheduleEngine.timeString(end)
            )
        }
        .sorted { $0.startDate < $1.startDate }

        // Synthesize passing periods for implicit gaps between consecutive periods.
        // The schedule data has no explicit Passing entries — the gaps are implicit.
        // Without this, the worker never hears the passing period's bell and the
        // widget holds the previous period until the next class starts.
        var withPassing: [ScheduleActivityAttributes.ScheduledPeriod] = []
        for (i, period) in mapped.enumerated() {
            withPassing.append(period)
            guard i < mapped.count - 1 else { continue }
            let next = mapped[i + 1]
            let gap = next.startDate.timeIntervalSince(period.endDate)
            // ≤ 10 min = passing period. Longer gaps are already named (Break, Lunch).
            if gap > 0 && gap <= 600 {
                withPassing.append(ScheduleActivityAttributes.ScheduledPeriod(
                    periodNumber: nil,
                    displayName: "Passing",
                    colorHex: "#94A3B8",
                    startDate: period.endDate,
                    endDate: next.startDate,
                    endTimeString: ScheduleEngine.timeString(next.startDate)
                ))
            }
        }
        // Past slots are dropped only NOW, after passing periods are filled
        // in. Dropping them first lost the passing period you're standing in:
        // a card started at 8:50, between Period 1 (ending 8:50) and Period 2
        // (8:55), had no Period 1 to measure a gap from, so it showed
        // "Today · Regular Schedule" as if school hadn't started yet.
        guard upcomingOnly else { return withPassing }
        let now = Date()
        return withPassing.filter { $0.endDate > now }
    }

    private func extractPeriodNumber(from name: String) -> Int? {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, parts[0].lowercased() == "period" else { return nil }
        return Int(parts[1])
    }
}

extension ScheduleActivityAttributes {
    /// Every Live Activity except the preview — the ones the broadcasts and
    /// the school day are about.
    static var realActivities: [Activity<ScheduleActivityAttributes>] {
        Activity<ScheduleActivityAttributes>.activities.filter { $0.attributes.preview == nil }
    }
}
