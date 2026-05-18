//
//  BellScheduleDetector.swift
//  LaSalle Schedule
//
//  Heuristics for detecting whether an event is bell-schedule related
//  and for assigning EventCategory from title/description text.
//

import Foundation

enum BellScheduleDetector {

    // MARK: - Bell Schedule Detection

    private static let bellKeywords: [String] = [
        "bell schedule", "block schedule", "late start", "early release",
        "early dismissal", "schedule", "period", "modified day"
    ]

    static func looksLikeBellSchedule(title: String, description: String?) -> Bool {
        let combined = (title + " " + (description ?? "")).lowercased()
        return bellKeywords.contains { combined.contains($0) }
    }

    /// Title-only check — used for category assignment to avoid miscategorizing
    /// events that merely embed a schedule table in their description.
    static func looksLikeBellScheduleTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        return bellKeywords.contains { t.contains($0) }
    }

    // MARK: - Category Inference

    static func category(title: String, description: String?) -> EventCategory {
        let t = title.lowercased()
        // Check bell schedule ONLY on title — not description.
        // Some events (e.g. Professional Dress Day) embed a bell schedule table
        // in their description but are not themselves schedule events.
        if looksLikeBellScheduleTitle(title) { return .bellSchedule }
        if t.contains("game") || t.contains("match") || t.contains("tournament")
            || t.contains("athletic") || t.contains("sport")
            || t.contains("golf") || t.contains("tennis") || t.contains("swim")
            || t.contains("basketball") || t.contains("baseball") || t.contains("softball")
            || t.contains("soccer") || t.contains("football") || t.contains("volleyball")
            || t.contains("track") || t.contains("cross country") || t.contains("wrestling")
            || t.contains("lacrosse") || t.contains("vs.") || t.contains(" vs ") { return .athletic }
        if t.contains("mass") || t.contains("liturgy") || t.contains("prayer")
            || t.contains("retreat") || t.contains("service") { return .liturgy }
        if t.contains("exam") || t.contains("test") || t.contains("finals")
            || t.contains("graduation") || t.contains("ap ") { return .academic }
        if t.contains("holiday") || t.contains("break") || t.contains("no school")
            || t.contains("christmas") || t.contains("thanksgiving") { return .holiday }
        return .other
    }
}
