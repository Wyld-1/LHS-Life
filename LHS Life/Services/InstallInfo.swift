//
//  InstallInfo.swift
//  LHS Life
//
//  What the worker is told about the phone it's hearing from: a random
//  per-install ID (problem reports only), the app build, the iOS version,
//  and which APNs environment this build was signed for. Nothing here names
//  a student or a phone model.
//

import Foundation
import OSLog
import UIKit

enum InstallInfo {

    // MARK: - Anonymous install ID

    /// The key predates this file — it lived in PushTokenService when the ID
    /// keyed push registrations — and must not change: existing installs keep
    /// the ID their earlier problem reports were filed under.
    private static let deviceIdKey = "lhs_device_id"

    /// A random UUID minted on first use and kept until Delete All Data.
    /// Sent only with problem reports, so the worker's /status page can tell
    /// "one phone, five times" from "five phones" — never with bell reports.
    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIdKey)
        return new
    }

    /// For Delete All Data. The next problem report mints a new ID.
    static func resetDeviceId() {
        UserDefaults.standard.removeObject(forKey: deviceIdKey)
    }

    // MARK: - Build identity
    //
    // App build + iOS version only. Deliberately NOT the hardware model:
    // utsname.machine ("iPhone16,1") is fingerprinting-adjacent, these
    // records sit next to a persistent ID for a few hundred minors, and no
    // debugging question so far has needed it. These two DO earn their
    // place — "which build is this device on" is the question that has come
    // up over and over.
    //
    // UIDevice.current.name is not used either: since iOS 16 it returns the
    // model name rather than the user's nickname unless the
    // user-assigned-device-name entitlement is granted by Apple.

    /// e.g. "1.3.0 (1)"
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// e.g. "26.1"
    static var osVersion: String {
        UIDevice.current.systemVersion
    }

    // MARK: - APNs environment
    //
    // Derived from the ACTUAL aps-environment entitlement, not from #if DEBUG.
    //
    // Those are independent switches: aps-environment comes from the
    // $(APS_ENVIRONMENT) build setting and the provisioning profile, while
    // DEBUG comes from the build configuration. A Release build run from
    // Xcode is signed with a development profile, so it talks to the APNs
    // sandbox while #if DEBUG reports "production". Broadcast channels belong
    // to one environment: a card subscribed to the production channel on a
    // sandbox build never hears a single push, and nothing says why.
    //
    // embedded.mobileprovision is present in development, ad-hoc, and
    // TestFlight-from-Xcode builds; the App Store strips it. So: no profile
    // means a real App Store build (production). A profile whose
    // aps-environment is "development" means sandbox. Anything else is
    // production.
    //
    // A `let`, worked out once: the entitlement can't change while the app
    // runs, and this reads a file.

    /// "production" or "sandbox" — the strings the worker expects.
    static let apnsEnvironment: String = {
        // The simulator has no provisioning profile, but its push service is
        // always the sandbox (verified Oct 19: apsd logs "development").
        // Without this, simulator cards subscribed to the production channel
        // and failed to start.
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // isoLatin1, NOT ascii: the file is a binary CMS blob and
              // .ascii decoding returns nil on any byte >127 — so the
              // original version of this check silently failed on every
              // build and fell through to "production". isoLatin1 maps all
              // 256 byte values, so the embedded plist text survives.
              let raw = String(data: data, encoding: .isoLatin1)
        else {
            LHSLogger.liveActivity.notice("apnsEnvironment: no embedded profile → production (App Store build)")
            return "production"
        }

        guard let range = raw.range(of: "<key>aps-environment</key>") else {
            // Profile present but no push entitlement at all — a card on a
            // broadcast channel will fail to start. Report production rather
            // than guess; the start failure is what gets reported.
            LHSLogger.liveActivity.error("apnsEnvironment: profile has NO aps-environment entitlement")
            return "production"
        }
        let tail = raw[range.upperBound...].prefix(200)
        let environment = tail.contains("development") ? "sandbox" : "production"
        LHSLogger.liveActivity.notice("apnsEnvironment: profile says \(environment, privacy: .public)")
        return environment
        #endif
    }()
}
