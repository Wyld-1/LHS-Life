//
//  CacheService.swift
//  LaSalle Schedule
//
//  Persists events to disk between app launches using JSON in the app's
//  Caches directory. No UserDefaults bloat, no Core Data overhead.
//

import Foundation

final class CacheService {

    private let fileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("lasalle_events.json")
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func saveEvents(_ events: [SchoolEvent]) {
        do {
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[CacheService] Failed to save events: \(error)")
        }
    }

    func loadEvents() -> [SchoolEvent]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([SchoolEvent].self, from: data)
        } catch {
            print("[CacheService] Failed to load events: \(error)")
            return nil
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Age of the cache file, nil if no cache exists.
    var cacheAge: TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(modified)
    }

    /// True if cache is older than the given interval (default 1 hour).
    func isCacheStale(olderThan interval: TimeInterval = 3600) -> Bool {
        guard let age = cacheAge else { return true }
        return age > interval
    }
}
