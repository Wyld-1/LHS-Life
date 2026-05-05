//
//  DateHelpers.swift
//  LHS Life
//
//  Date calculation helpers used by HomeworkPopup and DateHelperTests.
//  Extracted here so they can be unit-tested without UI dependencies.
//

import Foundation

/// Returns midnight Pacific of the day after `date`.
func nextDay(from date: Date = Date()) -> Date {
    let cal = Calendar.current
    return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
}

/// Returns midnight Pacific of the coming Monday after `date`.
/// If `date` is already a Monday, returns the NEXT Monday (7 days later).
func nextMonday(from date: Date = Date()) -> Date {
    let cal = Calendar.current
    let today = cal.startOfDay(for: date)
    let weekday = cal.component(.weekday, from: today) // 1=Sun, 2=Mon … 7=Sat
    // Days until next Monday: if today is Mon (2), skip to next week (7 days).
    let daysUntilMonday = weekday == 2 ? 7 : (9 - weekday) % 7
    return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
}
