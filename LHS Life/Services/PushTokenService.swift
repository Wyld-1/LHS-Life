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
import UIKit

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

    /// For Delete All Data. The next registration mints a new ID.
    static func resetDeviceId() {
        UserDefaults.standard.removeObject(forKey: "lhs_device_id")
        UserDefaults.standard.removeObject(forKey: signatureKey)
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

    // MARK: - Build identity
    //
    // App build + iOS version only. Deliberately NOT the hardware model:
    // utsname.machine ("iPhone16,1") is fingerprinting-adjacent, this is a
    // server-side record keyed to a persistent ID for a few hundred minors,
    // and no debugging question so far has needed it. These two DO earn their
    // place — "which build is this device on" is the question that has come
    // up over and over.
    //
    // UIDevice.current.name is not used either: since iOS 16 it returns the
    // model name rather than the user's nickname unless the
    // user-assigned-device-name entitlement is granted by Apple.

    /// e.g. "1.21 (1)"
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// e.g. "26.1"
    static var osVersion: String {
        UIDevice.current.systemVersion
    }

    // MARK: - Register

    // Deduplicates registrations.
    //
    // Persisted rather than in-memory: reconnect() now re-registers on every
    // launch, and an in-memory flag resets with the process — so a student
    // opening the app six times a day would spend six KV writes against a
    // 1,000/day account-wide cap.
    //
    // The signature covers everything the worker stores plus the date, so a
    // write happens when the payload genuinely changes (new schedule, rotated
    // token, new build) and otherwise at most once per device per day. That
    // daily floor is deliberate: it self-heals a device whose record was lost
    // or whose registry was rebuilt.
    private static let signatureKey = "lhs_last_registration_signature"

    private static func registrationSignature(
        token: String,
        environment: String,
        transitions: [Int],
        endMinutes: Int
    ) -> String {
        let day = DateFormatter.isoDay.string(from: Date())
        return [
            day,
            token,
            environment,
            appVersion,
            osVersion,
            transitions.map(String.init).joined(separator: ","),
            String(endMinutes)
        ].joined(separator: "|")
    }

    /// What the worker said about this registration.
    enum RegistrationResult: Equatable {
        case registered
        /// The school's server is full — see the worker's capacity gate. The
        /// device is NOT registered and no pushes will arrive, so a Live
        /// Activity started now would freeze on its first period.
        case overCapacity(contact: String)
        case failed
    }

    @discardableResult
    static func register(token: Data, periods: [ScheduleActivityAttributes.ScheduledPeriod]) async -> RegistrationResult {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()

        let apnsEnvironment = Self.apnsEnvironment
        let cal = Calendar.current
        let transitions = periods.map {
            cal.component(.hour, from: $0.startDate) * 60 + cal.component(.minute, from: $0.startDate)
        }
        let endMinutes = periods.last.map {
            cal.component(.hour, from: $0.endDate) * 60 + cal.component(.minute, from: $0.endDate)
        } ?? 0

        let signature = registrationSignature(
            token: tokenString,
            environment: apnsEnvironment,
            transitions: transitions,
            endMinutes: endMinutes
        )
        if UserDefaults.standard.string(forKey: signatureKey) == signature {
            LHSLogger.liveActivity.notice("PushToken: unchanged since last registration, skipping")
            return .registered
        }

        LHSLogger.liveActivity.notice("PushToken: registering \(tokenString.prefix(16), privacy: .public)…")

        guard let url = URL(string: "\(workerURL)/register") else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConstants.workerSecret)", forHTTPHeaderField: "Authorization")
        struct RegisterBody: Encodable {
            let deviceId: String
            let pushToken: String
            let environment: String
            let transitions: [Int]   // slotStartMinutes for each period start
            let endMinutes: Int      // last period's end time — triggers the dismissal push
            let appVersion: String   // e.g. "1.21 (1)" — which build is misbehaving
            let osVersion: String    // e.g. "26.1"
        }
        request.httpBody = try? JSONEncoder().encode(RegisterBody(
            deviceId: deviceId,
            pushToken: tokenString,
            environment: apnsEnvironment,
            transitions: transitions,
            endMinutes: endMinutes,
            appVersion: Self.appVersion,
            osVersion: Self.osVersion
        ))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // Checked before the status code, not after it. The worker
            // refuses with 507 so that OLDER builds fall into their failure
            // branch and retry later instead of caching a false success; this
            // build recognises the refusal by its payload, so the exact code
            // it arrives with never matters.
            if let payload = try? JSONDecoder().decode(RegisterResponse.self, from: data),
               payload.status == "over_capacity" {
                // Deliberately NOT saving the signature: a slot may free up
                // tomorrow, and the app should ask again rather than remember
                // the refusal forever.
                LHSLogger.liveActivity.error(
                    "PushToken: REFUSED — server at capacity (\(payload.registered ?? -1)/\(payload.limit ?? -1))"
                )
                return .overCapacity(contact: payload.contact ?? "the school office")
            }

            if status == 200 {
                UserDefaults.standard.set(signature, forKey: signatureKey)
                // deviceId is logged so a worker log line can be matched to
                // a specific handset — essential when two devices (Xcode and
                // TestFlight) are registered at the same time and you need to
                // know which one the worker is talking about.
                LHSLogger.liveActivity.notice(
                    """
                    PushToken: registered — HTTP \(status) env: \(apnsEnvironment, privacy: .public) \
                    build: \(Self.appVersion, privacy: .public) iOS \(Self.osVersion, privacy: .public) \
                    deviceId: \(Self.deviceId, privacy: .public) transitions: \(transitions.count) \
                    first: \(transitions.first ?? -1) last: \(transitions.last ?? -1) end: \(endMinutes)
                    """
                )
                return .registered
            }

            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            LHSLogger.liveActivity.error("PushToken: registration FAILED — HTTP \(status): \(body, privacy: .public)")
            return .failed
        } catch {
            LHSLogger.liveActivity.error("PushToken: registration network error — \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    /// The worker's JSON reply to /register.
    private struct RegisterResponse: Decodable {
        let status: String
        let limit: Int?
        let registered: Int?
        let contact: String?
        let message: String?
    }

    // MARK: - Unregister

    static func unregister() async {
        guard let url = URL(string: "\(workerURL)/unregister") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConstants.workerSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["deviceId": deviceId])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Clear the signature so the next launch re-registers rather than
            // deduping against a registration the worker no longer has.
            UserDefaults.standard.removeObject(forKey: signatureKey)
            LHSLogger.liveActivity.notice("PushToken: unregistered — HTTP \(status)")
        } catch {
            LHSLogger.liveActivity.error("PushToken: unregister failed — \(String(describing: error), privacy: .public)")
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
