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
    // trivially discoverable: /status lists device IDs and /unregister takes
    // them, so an open worker is a one-command way to kill Live Activities
    // school-wide. Rotate it here and in Cloudflare together.
    static let workerSecret = "com.lasalleyakima.lhslife"

    // MARK: - Privacy Policy
    // Shown in the app by PrivacyPolicyView, rendered from
    // Resources/PRIVACY.md — no URL, so nothing to break when the repo moves.
    // App Store Connect still needs its own hosted copy of the same text.
}
