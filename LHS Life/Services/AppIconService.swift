//
//  AppIconService.swift
//  LHS Life
//
//  Seasonal app icons — the Halloween L, and whatever comes next.
//
//  HOW A SEASON SHIPS: the seasonal icon goes out as the app's PRIMARY icon
//  in an App Store update (ASSETCATALOG_COMPILER_APPICON_NAME), and the
//  everyday icon rides along as an ALTERNATE. Auto-update swaps the Home
//  Screen icon overnight with no prompt — the way Spotify did its 20th
//  anniversary. Switching from inside the app would always show iOS's
//  "You have changed the icon" alert, and there is no approved way to hide it.
//
//  A student who would rather not gets a card on their first open (see
//  AppIconIntroCard) and a picker in Settings. Choosing Classic is the one
//  time that iOS alert appears, and it's the student's own tap that causes it.
//
//  ENDING A SEASON: ship an update with the primary icon set back to
//  "LHS Life Icon", the alternate list emptied, and `season` set to nil. A
//  student who picked Classic keeps a leftover alternate name that iOS
//  ignores once that alternate is gone — they see the classic icon either way.
//
//  STARTING THE NEXT ONE: add its .icon file, make it the primary, put
//  "LHS Life Icon" back in the alternate list, render a preview into the asset
//  catalog, and give `season` a new id so the card shows once again. Anyone
//  who chose Classic last time stays on Classic; the card offers them the new
//  one instead of assuming.
//

import SwiftUI
import OSLog
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case seasonal, classic
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppIconService {
    static let shared = AppIconService()

    struct Season {
        /// Unique per season AND year, so next Halloween's card isn't
        /// suppressed by this one's.
        let id: String
        let name: String
        /// A rendered copy of the icon in Assets.xcassets. The real icon
        /// can't be loaded as an image at runtime, so the picker shows this.
        let previewAsset: String
    }

    /// The season this build dresses up for — the icon set as its primary.
    /// nil in a build that ships the classic icon as primary.
    static let season: Season? = Season(
        id: "halloween-2026",
        name: "Halloween",
        previewAsset: "IconPreviewHalloween"
    )

    /// The everyday icon, under its alternate-icon name (the .icon file's).
    static let classicIconName = "LHS Life Icon"
    static let classicPreviewAsset = "IconPreviewClassic"

    private static let introducedKey = "lhs_icon_intro_season"

    private(set) var current: AppIconChoice

    private init() {
        current = UIApplication.shared.alternateIconName == Self.classicIconName ? .classic : .seasonal
    }

    /// Whether there is a choice to make. No season, nothing to pick; and
    /// iOS doesn't support alternate icons everywhere — on a Mac this app's
    /// icon is fixed.
    var canChoose: Bool {
        Self.season != nil && UIApplication.shared.supportsAlternateIcons
    }

    /// The card shows once per season, the first time the app opens.
    var shouldIntroduce: Bool {
        guard canChoose, let season = Self.season else { return false }
        return UserDefaults.standard.string(forKey: Self.introducedKey) != season.id
    }

    func markIntroduced() {
        guard let season = Self.season else { return }
        UserDefaults.standard.set(season.id, forKey: Self.introducedKey)
    }

    /// Switches the Home Screen icon. iOS shows its own confirmation alert;
    /// nothing here can or should suppress it.
    func choose(_ choice: AppIconChoice) async {
        guard canChoose, choice != current else { return }
        let name: String? = choice == .classic ? Self.classicIconName : nil
        do {
            try await UIApplication.shared.setAlternateIconName(name)
            current = choice
            LHSLogger.appIcon.notice("App icon set to \(choice.rawValue, privacy: .public)")
        } catch {
            LHSLogger.appIcon.error("App icon change failed: \(String(describing: error), privacy: .public)")
        }
    }
}
