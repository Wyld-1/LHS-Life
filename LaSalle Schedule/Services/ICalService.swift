//
//  ICalService.swift
//  LaSalle Schedule
//
//  Fetches and parses the CalendarWiz iCal feed.
//  No third-party dependencies — pure Swift + Foundation.
//

import Foundation

final class ICalService {

    // MARK: - Config

    private static let feedURL = URL(string: "https://www.calendarwiz.com/CalendarWiz_iCal.php?crd=lasalleyakima&ical_days_back=30&ical_days_ahead=180")!

    // MARK: - Fetch

    /// Fetches the iCal feed and returns parsed events.
    func fetchEvents() async throws -> [SchoolEvent] {
        let (data, response) = try await URLSession.shared.data(from: Self.feedURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ICalError.badResponse
        }
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ICalError.decodingFailed
        }
        return try ICalParser.parse(raw)
    }
}

// MARK: - ICalError

enum ICalError: LocalizedError {
    case badResponse
    case decodingFailed
    case malformedFeed(reason: String)

    var errorDescription: String? {
        switch self {
        case .badResponse:              return "Received a bad response from the calendar server."
        case .decodingFailed:           return "Could not decode the calendar feed."
        case .malformedFeed(let r):     return "Malformed calendar feed: \(r)"
        }
    }
}
