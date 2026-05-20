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

    // MARK: - Register

    static func register(token: Data) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        print("[PushToken] Registering token: \(tokenString.prefix(16))...")

        guard let url = URL(string: "\(workerURL)/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct RegisterBody: Encodable {
            let deviceId: String
            let pushToken: String
            let environment: String
        }
        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif
        request.httpBody = try? JSONEncoder().encode(RegisterBody(
            deviceId: deviceId,
            pushToken: tokenString,
            environment: apnsEnvironment
        ))

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[PushToken] Registered — HTTP \(status)")
        } catch {
            print("[PushToken] Registration failed: \(error)")
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

    static func observeTokenUpdates<A: ActivityAttributes>(
        for activity: Activity<A>
    ) {
        Task {
            for await token in activity.pushTokenUpdates {
                await register(token: token)
            }
            // Token stream ended — activity ended, unregister
            await unregister()
        }
    }
}
