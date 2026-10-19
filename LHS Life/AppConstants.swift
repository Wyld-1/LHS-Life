//
//  AppConstants.swift
//  LHS Life
//
//  Single source of truth for IDs and URLs that change year-to-year.
//  At the start of each school year, update the values in this file only.
//

import Foundation

enum AppConstants {

    // MARK: - TeamReach
    // Update teamReachChannelID each year when ASB creates the new announcement channel.
    // Format: teamreach://team/{id}
    // To find the ID: open TeamReach, navigate to the channel, share → copy link.

    static let teamReachChannelID = "LHSASB2026-2027"
    static var teamReachURL: URL {
        URL(string: "com.teamreach://")! //teamreach://team/\(teamReachChannelID)
    }

    // MARK: - Push Worker
    // Sent as a bearer token on every request to the Live Activity worker.
    // Must match CLIENT_SECRET in the Cloudflare dashboard.
    //
    // Not a real secret — it ships in the binary, and anyone who unpacks the
    // app can read it. It exists to keep the worker's routes from being
    // trivially discoverable: /status lists problem reports and /bells
    // decides when every phone's card gets pushed, so an open worker is a
    // one-command way to disrupt Live Activities school-wide. Rotate it here
    // and in Cloudflare together.
    static let workerSecret = "com.lasalleyakima.lhslife"

    /// The Live Activity worker. One place to change when the worker moves to
    /// the school's own Cloudflare account — it is used by both the bell
    /// reports (BellReporter) and the problem reports (IssueReporter).
    static let workerURL = "https://lhslife-liveactivityworker.liam-lefohn.workers.dev"

    // MARK: - Broadcast channels
    //
    // Live Activities subscribe to ONE channel and the Worker sends one push
    // per bell to it; Apple fans it out to every phone. Each card works out
    // its own class from the schedule it carries, so one message serves
    // every student's schedule. Channel IDs aren't secrets. A channel made
    // in one APNs environment can't be used in the other.

    /// Sandbox (Xcode builds). Created 2026-10-19, storage policy "Most
    /// Recent Message Stored".
    static let broadcastChannelSandbox = "oikr1cvOEfEAAPYv+t4beg=="

    /// Production (TestFlight and App Store builds).
    static let broadcastChannelProduction = "JJ+34svREfEAAGpsYJ+BOQ=="

    /// The channel for the APNs environment this build was actually signed
    /// for — read from the provisioning profile, not #if DEBUG, since a
    /// Release build run from Xcode is still a sandbox build. BellReporter
    /// names the same environment, so the worker broadcasts where this card
    /// is listening.
    static var broadcastChannel: String {
        InstallInfo.apnsEnvironment == "sandbox" ? broadcastChannelSandbox : broadcastChannelProduction
    }

    // MARK: - App Store

    /// The app's numeric Apple ID (App Store Connect → App Information).
    static let appStoreID = "6812553629"

    /// Opens the App Store straight to the "Write a Review" sheet.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    // MARK: - Privacy Policy
    // Shown in the app by PrivacyPolicyView, rendered from
    // Resources/PRIVACY.md — no URL, so nothing to break when the repo moves.
    // App Store Connect still needs its own hosted copy of the same text.
}
