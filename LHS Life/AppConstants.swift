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

    // MARK: - Privacy Policy
    // Apple requires a link in the app AND in App Store Connect — keep both
    // pointing here. Renders Docs/PRIVACY.md from main, so it only resolves
    // once that file is pushed.

    static let privacyPolicyURL = URL(string: "https://github.com/Wyld-1/LHS-Life/blob/main/Docs/PRIVACY.md")!
}
