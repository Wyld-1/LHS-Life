//
//  DataResetService.swift
//  LHS Life
//
//  Delete All Data, all of it. UserSettings.deleteAllData() resets what the
//  app stores in UserDefaults and iCloud, but two things live out of its
//  reach — and UserSettings is compiled into the widget too, so it can't
//  import WebKit or talk to the worker:
//
//    1. Web logins. PowerSchool, Schoology, and lunch ordering keep their
//       cookies in WebKit's default data store. Without clearing it, the next
//       person to sign in on a shared iPad lands in the previous student's
//       grades.
//    2. The Live Activity worker's record of this device.
//    3. The calendar — in memory, the disk cache, and the app-group blob the
//       widgets render from.
//
//  Deliberately still untouched: anything saved to Calendar or Reminders.
//  See UserSettings.deleteAllData() for why.
//

import Foundation
import WidgetKit
internal import WebKit

@MainActor
enum DataResetService {

    static func deleteAllData(settings: UserSettings) {
        // Settings first and synchronously — this flips accessApproved, which
        // swaps the whole tab container (and its web views) out for the
        // sign-in screen before the cleanup below runs.
        settings.deleteAllData()

        // The calendar: in memory, on disk, and in the app group the widgets
        // read from. Also synchronous, so the sign-in screen is already
        // standing on an empty store by the time anyone can type into it.
        CalendarStore.shared.clearAll()

        // Widgets hold their own rendered timelines and would otherwise keep
        // showing the cleared schedule until their next scheduled refresh.
        WidgetCenter.shared.reloadAllTimelines()

        Task {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            )

            // End before unregistering, so the activity can't rotate its
            // token and re-register in between.
            await LiveActivityService.shared.end()
            await PushTokenService.unregister()

            // A fresh random ID next time, so nothing the worker or its logs
            // saw before the reset can be tied to whoever uses this device next.
            PushTokenService.resetDeviceId()
        }
    }
}
