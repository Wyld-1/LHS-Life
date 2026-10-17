//
//  AppIconService.swift
//  LHS Life
//
//  Holiday app icons — Halloween, Thanksgiving, Christmas and Easter.
//
//  Every icon ships in the app; nothing waits on an App Store update. The
//  classic icon is the app's PRIMARY icon, and each holiday icon is an
//  ALTERNATE (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES). Around each
//  holiday the date opens a window: the App Icon section appears in
//  Settings, and on the first open of the window a card slides up offering
//  the holiday icon. Outside every window the section hides — unless the
//  student is still wearing a holiday icon, in which case it stays so they
//  can always get back to Classic.
//
//  Switching always shows iOS's "You have changed the icon" alert. There is
//  no approved way to hide it, and it only ever follows the student's tap.
//
//  Known and kept on purpose: a student who picks a holiday icon and never
//  switches back keeps it all year. If it's their favorite, it's a nice
//  little easter egg.
//
//  ADDING A HOLIDAY: make its .icon in Icon Composer, add the file to the
//  app target, add its name to the alternate icon list in Build Settings,
//  add a preview to Scripts/render-icon-previews.sh and run it, then add an
//  entry to `holidays` below.
//

import SwiftUI
import OSLog
import UIKit

@MainActor
@Observable
final class AppIconService {
    static let shared = AppIconService()

    /// One choosable icon. `alternateName` is nil for the classic icon,
    /// which is the app's primary icon.
    struct Icon: Identifiable, Hashable {
        let id: String
        let name: String
        let alternateName: String?
        /// A rendered copy of the icon in Assets.xcassets — the real icon
        /// can't be loaded as an image at runtime. Kept current by
        /// Scripts/render-icon-previews.sh.
        let previewAsset: String
    }

    struct Holiday {
        let icon: Icon
        /// The dates the icon is offered, for the holiday that falls in or
        /// around `year`. The end is exclusive.
        let window: (_ year: Int, _ calendar: Calendar) -> DateInterval?
    }

    static let classic = Icon(id: "classic", name: "Classic",
                              alternateName: nil, previewAsset: "IconPreviewClassic")

    static let holidays: [Holiday] = [
        Holiday(
            icon: Icon(id: "halloween", name: "Halloween",
                       alternateName: "LHS Life Halloween", previewAsset: "IconPreviewHalloween"),
            // All of October.
            window: { year, cal in
                interval(cal, from: (year, 10, 1), to: (year, 11, 1))
            }
        ),
        Holiday(
            icon: Icon(id: "thanksgiving", name: "Thanksgiving",
                       alternateName: "LHS Life Thanksgiving", previewAsset: "IconPreviewThanksgiving"),
            // November 1 through the Sunday after Thanksgiving (the fourth
            // Thursday), so the long weekend keeps it.
            window: { year, cal in
                guard let thanksgiving = cal.date(from: DateComponents(
                    year: year, month: 11, weekday: 5, weekdayOrdinal: 4
                )), let start = cal.date(from: DateComponents(year: year, month: 11, day: 1)),
                    let end = cal.date(byAdding: .day, value: 4, to: thanksgiving)
                else { return nil }
                return DateInterval(start: start, end: end)
            }
        ),
        Holiday(
            icon: Icon(id: "christmas", name: "Christmas",
                       alternateName: "LHS Life Christmas", previewAsset: "IconPreviewChristmas"),
            // December 1 through Epiphany, January 6.
            window: { year, cal in
                interval(cal, from: (year, 12, 1), to: (year + 1, 1, 7))
            }
        ),
        Holiday(
            icon: Icon(id: "easter", name: "Easter",
                       alternateName: "LHS Life Easter", previewAsset: "IconPreviewEaster"),
            // Palm Sunday through Divine Mercy Sunday, the week after Easter.
            window: { year, cal in
                guard let easter = easterSunday(year: year, calendar: cal),
                      let start = cal.date(byAdding: .day, value: -7, to: easter),
                      let end = cal.date(byAdding: .day, value: 8, to: easter)
                else { return nil }
                return DateInterval(start: start, end: end)
            }
        ),
    ]

    private static let introducedKey = "lhs_icon_intro_season"

    /// The icon on the Home Screen right now.
    private(set) var current: Icon

    private init() {
        let name = UIApplication.shared.alternateIconName
        // An alternate name this build doesn't know (one a past build used)
        // is shown by iOS as the primary icon, so it reads as Classic too.
        current = Self.holidays.first { $0.icon.alternateName == name }?.icon ?? Self.classic
    }

    // MARK: - Seasons

    /// The holiday whose window contains `date`, and that window.
    /// `date` defaults to DebugClock's now, so -demoClock can visit a holiday.
    static func activeHoliday(on date: Date? = nil) -> (holiday: Holiday, window: DateInterval)? {
        let date = date ?? DebugClock.shared.now
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        // The year before too: Christmas's window starts in one year and
        // ends in the next.
        for y in [year, year - 1] {
            for holiday in holidays {
                if let window = holiday.window(y, cal), window.contains(date) {
                    return (holiday, window)
                }
            }
        }
        return nil
    }

    /// iOS doesn't support alternate icons everywhere — on a Mac this app's
    /// icon is fixed.
    var supportsIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    /// Settings shows the App Icon section during a holiday, and any time a
    /// holiday icon is still on the Home Screen so Classic is always a tap
    /// away.
    var showsSection: Bool {
        supportsIcons && (Self.activeHoliday() != nil || current != Self.classic)
    }

    /// The tiles to offer: Classic first, then this holiday's icon, then the
    /// one the student is wearing if it's from a past holiday.
    var options: [Icon] {
        var icons = [Self.classic]
        if let active = Self.activeHoliday()?.holiday.icon { icons.append(active) }
        if !icons.contains(current) { icons.append(current) }
        return icons
    }

    /// The card shows once per holiday per year, on the first open inside
    /// the window.
    var shouldIntroduce: Bool {
        guard supportsIcons, let id = Self.activeSeasonID else { return false }
        return UserDefaults.standard.string(forKey: Self.introducedKey) != id
    }

    func markIntroduced() {
        guard let id = Self.activeSeasonID else { return }
        UserDefaults.standard.set(id, forKey: Self.introducedKey)
    }

    /// "christmas-2026" — the holiday and the year its window opened, so the
    /// Christmas that ends in January isn't counted as a new season.
    private static var activeSeasonID: String? {
        guard let (holiday, window) = activeHoliday() else { return nil }
        return "\(holiday.icon.id)-\(Calendar.current.component(.year, from: window.start))"
    }

    // MARK: - Switching

    /// Switches the Home Screen icon. iOS shows its own confirmation alert;
    /// nothing here can or should suppress it.
    func choose(_ icon: Icon) async {
        guard supportsIcons, icon != current else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            current = icon
            LHSLogger.appIcon.notice("App icon set to \(icon.id, privacy: .public)")
        } catch {
            LHSLogger.appIcon.error("App icon change failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Date helpers

    private static func interval(_ cal: Calendar, from a: (Int, Int, Int), to b: (Int, Int, Int)) -> DateInterval? {
        guard let start = cal.date(from: DateComponents(year: a.0, month: a.1, day: a.2)),
              let end = cal.date(from: DateComponents(year: b.0, month: b.1, day: b.2))
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Western (Gregorian) Easter Sunday — the anonymous Gregorian algorithm
    /// ("Meeus/Jones/Butcher"). Exact for every year of the Gregorian
    /// calendar, so no table of dates to maintain.
    static func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
