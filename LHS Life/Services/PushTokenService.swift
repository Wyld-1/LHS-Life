//
//  PushTokenService.swift
//  LHS Life
//
//  Registers the Live Activity push token with the Cloudflare Worker.
//  Called whenever ActivityKit issues a new or updated token.
//
//  The worker stores tokens by deviceId (UUID persisted in UserDefaults)
//  so if the token rotates, it overwrites the old entry cleanly.
//

import Foundation
import ActivityKit
import OSLog

enum PushTokenService {

    private static let workerURL = "https://lhslife-liveactivityworker.liam-lefohn.workers.dev"

    // Persistent device ID — stable across app launches, used as the KV key
    static var deviceId: String {
        let key = "lhs_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    // MARK: - APNs environment
    //
    // Derived from the ACTUAL aps-environment entitlement, not from #if DEBUG.
    //
    // Those are independent switches: aps-environment comes from the
    // $(APS_ENVIRONMENT) build setting and the provisioning profile, while
    // DEBUG comes from the build configuration. A Release build run from
    // Xcode is signed with a development profile — so it gets a SANDBOX
    // token while #if DEBUG reports "production". The worker then routes to
    // api.push.apple.com, APNs answers 400 BadDeviceToken, and the worker
    // deletes the device from its registry — killing updates for the rest of
    // the day, silently.
    //
    // embedded.mobileprovision is present in development, ad-hoc, and
    // TestFlight-from-Xcode builds; the App Store strips it. So: no profile
    // means a real App Store build (production). A profile whose
    // aps-environment is "development" means sandbox. Anything else is
    // production.
    static var apnsEnvironment: String {
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
            // Profile present but no push entitlement at all — Activity.request
            // with pushType: .token will fail. Report production and let the
            // worker's fallback sort it out rather than guessing.
            LHSLogger.liveActivity.error("apnsEnvironment: profile has NO aps-environment entitlement")
            return "production"
        }
        let tail = raw[range.upperBound...].prefix(200)
        let environment = tail.contains("development") ? "sandbox" : "production"
        LHSLogger.liveActivity.notice("apnsEnvironment: profile says \(environment, privacy: .public)")
        return environment
    }

    // MARK: - Register

    // Deduplicates rapid registrations of the same token. ActivityKit sometimes
    // delivers the initial token via both activity.pushToken AND the first
    // pushTokenUpdates emission within milliseconds of each other.
    private static var lastRegisteredToken: String?

    static func register(token: Data, periods: [ScheduleActivityAttributes.ScheduledPeriod]) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()

        if lastRegisteredToken == tokenString {
            print("[PushToken] Skipping duplicate registration: \(tokenString.prefix(16))...")
            return
        }

        print("[PushToken] Registering token: \(tokenString.prefix(16))...")

        guard let url = URL(string: "\(workerURL)/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct RegisterBody: Encodable {
            let deviceId: String
            let pushToken: String
            let environment: String
            let transitions: [Int]   // slotStartMinutes for each period start
            let endMinutes: Int      // last period's end time — triggers the dismissal push
        }
        let apnsEnvironment = Self.apnsEnvironment
        let cal = Calendar.current
        let transitions = periods.map {
            cal.component(.hour, from: $0.startDate) * 60 + cal.component(.minute, from: $0.startDate)
        }
        let endMinutes = periods.last.map {
            cal.component(.hour, from: $0.endDate) * 60 + cal.component(.minute, from: $0.endDate)
        } ?? 0
        request.httpBody = try? JSONEncoder().encode(RegisterBody(
            deviceId: deviceId,
            pushToken: tokenString,
            environment: apnsEnvironment,
            transitions: transitions,
            endMinutes: endMinutes
        ))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                lastRegisteredToken = tokenString
                print("[PushToken] Registered — HTTP \(status) (\(apnsEnvironment))")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                print("[PushToken] Registration FAILED — HTTP \(status): \(body)")
            }
        } catch {
            print("[PushToken] Registration network error: \(error)")
        }
    }

    // MARK: - Unregister

    static func unregister() async {
        guard let url = URL(string: "\(workerURL)/unregister") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["deviceId": deviceId])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[PushToken] Unregistered — HTTP \(status)")
        } catch {
            print("[PushToken] Unregister failed: \(error)")
        }
    }

    // MARK: - Observe token updates for a live activity

    static func observeTokenUpdates(
        for activity: Activity<ScheduleActivityAttributes>,
        periods: [ScheduleActivityAttributes.ScheduledPeriod]
    ) {
        Task {
            for await token in activity.pushTokenUpdates {
                await register(token: token, periods: periods)  // re-sends on token rotation
            }
            // Token stream ended — activity ended, unregister
            await unregister()
        }
    }
}
