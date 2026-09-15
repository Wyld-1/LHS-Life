//
//  LoadingPhraseDeck.swift
//  LHS Life
//
//  Loading-screen phrase pool + shuffled-deck picker.
//
//  Same technique as EasterEggState: draw randomly from an unused pile until
//  it's empty, then reshuffle — guaranteeing every phrase is seen once before
//  any repeats, rather than plain .randomElement(), which can hand back the
//  same phrase on consecutive launches.
//
//  Kept as its own type rather than folded into EasterEggState — these are
//  loading words (something being readied), not the easter egg's quotes, and
//  the two pools have different content requirements: this one is seen by
//  every user on every launch, so it stays free of movie quotes and mottos.
//

import Foundation

// MARK: - Phrase pool

enum LoadingPhrases {
    static let all: [String] = [
        "Caramelizing onions…",
        "Polishing bells…",
        "Entering to learn…",
        "Rolling bolts…",
        "Waxing floors…",
        "Stacking chairs…",
        "Winding clocks…",
        "Testing mics…",
        "Refilling staplers…",
        "Tussling with projectors…",
        "Charging iPads…",
        "Leaving to serve…",
        "Sharpening pencils…",
        "Setting the table…",
        "Programming robots…",
        "Raising salmon…",
        "Designing graphics…",
        "Painting charcoal…",
        "Mocking trials…",
        "Photographing…",
        "Reading graphs…",
        "Writing papers…",
        "Solving equations…",
        "Touchdowning…",
        "Scoring hoops…",
        "Slow dancing…",
        "Debating…",
        "Rehearsing lines…",
        "Tuning instruments…",
        "Mixing paint…",
        "Dissecting frogs…",
        "Pinning wrestlers…",
        "Kneading dough…",
        "Glazing pottery…",
    ]
}

// MARK: - Shuffled deck

@MainActor
final class LoadingPhraseDeck {
    static let shared = LoadingPhraseDeck()

    private var unused: [String] = []
    private var last: String?

    private init() {
        refill()
    }

    /// Draws the next phrase. Call once per LaunchScreen instance and hold
    /// the result in @State — calling this from a computed property would
    /// draw a new phrase on every render.
    func draw() -> String {
        if unused.isEmpty { refill() }
        let phrase = unused.removeLast()
        last = phrase
        return phrase
    }

    private func refill() {
        var pool = LoadingPhrases.all
        // Keep the just-shown phrase out of the new shuffle's draw order
        // until the end, so a reshuffle can't hand back the same phrase two
        // launches in a row.
        if let last, let idx = pool.firstIndex(of: last) {
            pool.remove(at: idx)
            unused = pool.shuffled()
            unused.insert(last, at: 0)  // drawn last in this cycle (LIFO)
        } else {
            unused = pool.shuffled()
        }
    }
}
