//
//  EasterEggState.swift
//  LHS Life
//
//  Shared observable state + quote pool for the easter egg.
//
//  WHY THIS EXISTS — each tab has its own NavigationStack, and each
//  NavigationStack instantiates its own ScheduleHeaderPill with independent
//  @State. Without shared state, the easter egg activates on one tab and the
//  others know nothing about it. Lifting into @Observable means one instance
//  drives all four pills and the full-screen overlay identically.
//

import SwiftUI

// MARK: - Quote pool

enum EasterEggQuotes {
    static let all: [String] = [
        "Keep flying 🕊️",
        "Never hesitate 😝",
        "Fly long enough and the sun will rise",
        "Let's turn and burn",
        "Speed has never killed anyone. Stopping has.",
        "Built by Lion 🦁",
        "Are you watching closely?",
        "We live in a twilight world",
        "I ordered my hot sauce an hour ago",
        "There's a point at 7,000 RPM...",
        "Aren’t you a little short for a stormtrooper?",
        "Was that floating like a Cadillac or stinging like a Beamer?",
        "Verso l' alto",
        "Have fun storming the castle!",
        "Inconceivable!",
        "As you wish",
        "May the Schwartz be with you",
        "Do or do not. There is no try.",
        "One catastrophe at a time",
        "Time flies like an arrow. Fruit flies like a banana.",
        "Whiteboards are truly remarkable",
        "The shovel was a groundbreaking innovation",
        "It works on my machine",
        "To infinity and beyond!",
        "No capes!",
        "Where is my super suit?",
        "Ka-Chow!",
        "I'll put it simple: if you're goin' hard enough left, you'll find yourself turnin' right",
        "Fear is the mind killer",
        "The answer is 42.",
        "So long and thanks for the fish",
        "If you want a Lamborghini, stop working like you want a Honda",
        "That which you manifest is before you",
        "Why do they call it rush hour when no one moves?",
        "The journey of 1,000 miles began with a single step",
        "Fall seven times, stand up eight",
        "Luck is when preparation meets opportunity",
        "The obstacle is the way",
        "Not all those who wander are lost",
        "Your fear of looking stupid is holding you back",
        "The pessimist complains about the wind. The optimist expects it to change. The realist adjusts the sails.",
        "Ships are safe in harbor, but that's not what ships are for",
        "Make it work, make it right, make it fast",
        "Here's to the crazy ones...",
        "Think different",
        "Stay hungry, stay foolish",
        "Press on",
        "To be or not to be, that is the question",
        "Be still and know that I am God",
        "The Lord is my shepherd; there is nothing I shall want",
        "Enter to learn, leave to serve",
    ]
}

// MARK: - Shared state

@Observable
final class EasterEggState {
    static let shared = EasterEggState()

    // Visibility — EasterEggOverlay observes this
    var isVisible: Bool = false

    // Current displayed quote
    var currentQuote: String = ""

    // Incremented on every quote change so EasterEggOverlay's word-reveal
    // restarts cleanly even when the text itself repeats
    var quoteToken: Int = 0

    // Shuffled-deck state: pick randomly from unused until empty, then reshuffle
    private var unusedIndices: [Int] = []
    private var usedIndices: [Int] = []

    private init() {
        refillDeck()
    }

    // MARK: Public

    func nextQuote() {
        let quote = EasterEggQuotes.all[drawIndex()]
        currentQuote = quote
        quoteToken += 1
    }

    // MARK: Private

    private func drawIndex() -> Int {
        if unusedIndices.isEmpty { refillDeck() }
        let pick = unusedIndices.removeLast()
        usedIndices.append(pick)
        return pick
    }

    private func refillDeck() {
        // Shuffle all indices except the last one shown (if any) to avoid
        // the same quote appearing back-to-back across a reshuffle
        var indices = Array(0 ..< EasterEggQuotes.all.count)
        if let last = usedIndices.last {
            indices.removeAll { $0 == last }
            unusedIndices = indices.shuffled()
            unusedIndices.insert(last, at: 0) // push last to front so it's drawn last next cycle
        } else {
            unusedIndices = indices.shuffled()
        }
        usedIndices = []
    }
}
