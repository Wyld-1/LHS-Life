//
//  SchoolDayValueIntents.swift
//  LHS Life
//
//  Shortcuts actions that hand back VALUES, for automations — "set an alarm
//  an hour before school starts", "turn on a Focus when school's in".
//
//  The Siri intents next door speak an answer and show a card, which is right
//  for asking out loud but useless to a shortcut: there's nothing to pass to
//  the next action. These return a plain Date, String or Bool instead, and say
//  nothing, so they run silently inside an automation.
//
//  Every one takes an optional date and defaults to today. On a day without
//  school for this student (weekend, holiday, break, their Pathways day) the
//  time actions return nothing, which Shortcuts' "If … has any value" checks.
//
//  They answer from CalendarStore.schoolDay(on:), the same source as the app's
//  own header, so a shortcut and the app can't disagree.
//

import AppIntents
import Foundation

/// Shared plumbing: make sure there's data, then ask the store.
private enum SchoolDayLookup {
    @MainActor
    static func day(on date: Date?, store: CalendarStore, settings: UserSettings) async
        -> (start: Date, end: Date, scheduleName: String)?
    {
        guard settings.accessApproved else { return nil }
        await AppIntentSupport.ensureDataLoaded(store: store, settings: settings)
        return store.schoolDay(on: date ?? Date())
    }
}

struct GetSchoolStartTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get School Start Time"
    static let description = IntentDescription(
        "Returns when your first class starts — today, or on the date you pick. Returns nothing on days without school.",
        categoryName: "School Day"
    )

    @Parameter(title: "Date", description: "Leave empty for today.")
    var date: Date?

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    static var parameterSummary: some ParameterSummary {
        Summary("Get school start time on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Date?> {
        let day = await SchoolDayLookup.day(on: date, store: store, settings: settings)
        return .result(value: day?.start)
    }
}

struct GetSchoolEndTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get School End Time"
    static let description = IntentDescription(
        "Returns when your last class ends — today, or on the date you pick. Returns nothing on days without school.",
        categoryName: "School Day"
    )

    @Parameter(title: "Date", description: "Leave empty for today.")
    var date: Date?

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    static var parameterSummary: some ParameterSummary {
        Summary("Get school end time on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Date?> {
        let day = await SchoolDayLookup.day(on: date, store: store, settings: settings)
        return .result(value: day?.end)
    }
}

struct GetScheduleTypeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Schedule Type"
    static let description = IntentDescription(
        "Returns the kind of bell schedule — \"Regular Schedule\", \"Late Start Schedule\" and so on. Returns nothing on days without school.",
        categoryName: "School Day"
    )

    @Parameter(title: "Date", description: "Leave empty for today.")
    var date: Date?

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    static var parameterSummary: some ParameterSummary {
        Summary("Get schedule type on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let day = await SchoolDayLookup.day(on: date, store: store, settings: settings)
        return .result(value: day?.scheduleName)
    }
}

struct IsThereSchoolIntent: AppIntent {
    static let title: LocalizedStringResource = "Is There School"
    static let description = IntentDescription(
        "Returns true if you have school today, or on the date you pick.",
        categoryName: "School Day"
    )

    @Parameter(title: "Date", description: "Leave empty for today.")
    var date: Date?

    @Dependency var store: CalendarStore
    @Dependency var settings: UserSettings

    static var parameterSummary: some ParameterSummary {
        Summary("Is there school on \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let day = await SchoolDayLookup.day(on: date, store: store, settings: settings)
        return .result(value: day != nil)
    }
}
