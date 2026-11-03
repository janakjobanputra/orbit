import AppKit
import KeyboardShortcuts
import XCTest
@testable import Orbit

// Each test changes one setting and checks the effect through AppState, the same object the
// popover, menu bar and Settings preview read from. Grouped like the Settings window.

private let now = TestSupport.date(2026, 10, 31, 9, 47)

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 31, month: Int = 10) -> Date {
    TestSupport.date(2026, month, day, hour, minute)
}

private extension AppState {
    var agendaTitles: [[String]] { agendaDays.map { $0.events.map(\.title) } }
}

// MARK: - General

@MainActor
final class GeneralSettingsTests: XCTestCase {

    func testKeepCalendarOnTop() {
        XCTAssertEqual(SystemIntegration.popoverBehavior(keepCalendarOnTop: true), .applicationDefined)
        XCTAssertEqual(SystemIntegration.popoverBehavior(keepCalendarOnTop: false), .transient)
    }

    func testAppearanceOptions() async {
        let (state, _, _) = await StateFixture.make()
        let original = NSApp.appearance
        defer { NSApp.appearance = original }

        state.preferences.appearance = .light
        SystemIntegration.apply(state.preferences)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        state.preferences.appearance = .dark
        SystemIntegration.apply(state.preferences)
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)

        state.preferences.appearance = .system
        SystemIntegration.apply(state.preferences)
        XCTAssertNil(NSApp.appearance, "System follows the Mac's own setting")
    }

    func testGlobalShortcutDefaults() {
        XCTAssertEqual(KeyboardShortcuts.Name.toggleCalendar.defaultShortcut, .init(.c, modifiers: [.command, .shift]))
        XCTAssertEqual(KeyboardShortcuts.Name.joinNextMeeting.defaultShortcut, .init(.j, modifiers: [.command, .shift]))
    }

    func testEnableGlobalShortcuts() async {
        let (state, _, _) = await StateFixture.make()
        defer { KeyboardShortcuts.enable(KeyboardShortcuts.Name.allGlobal) }

        state.preferences.globalShortcutsEnabled = false
        SystemIntegration.apply(state.preferences)
        for name in KeyboardShortcuts.Name.allGlobal {
            XCTAssertFalse(KeyboardShortcuts.isEnabled(for: name), "\(name.rawValue) should be off")
        }

        state.preferences.globalShortcutsEnabled = true
        SystemIntegration.apply(state.preferences)
        for name in KeyboardShortcuts.Name.allGlobal {
            XCTAssertTrue(KeyboardShortcuts.isEnabled(for: name), "\(name.rawValue) should be on")
        }
    }

    func testJoinNextMeetingPicksMeetingInProgressOrNext() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Done", start: at(8), minutes: 30), link: "https://zoom.us/j/1")
            store.add(TestSupport.event("Standup", start: at(10), minutes: 15), link: "https://zoom.us/j/2")
            store.add(TestSupport.event("Review", start: at(11), minutes: 30), link: "https://meet.google.com/abc-defg-hij")
        }
        XCTAssertEqual(state.nextMeetingURL?.absoluteString, "https://zoom.us/j/2")
    }

    func testJoinStillWorksAfterTheMeetingStarts() async {
        let (state, _, clock) = await StateFixture.make(at: at(19, 25)) { store, _ in
            store.add(TestSupport.event("Call", start: at(19, 30), minutes: 30), link: "https://meet.google.com/abc-defg-hij")
            store.add(TestSupport.event("Later", start: at(20, 30), minutes: 30), link: "https://zoom.us/j/9")
        }
        for minute in [25, 30, 33, 40, 59] {
            clock.now = at(19, minute)
            state.refreshNow()
            XCTAssertEqual(state.nextMeetingURL?.host, "meet.google.com", "at 19:\(minute)")
        }
        clock.now = at(20, 0)
        state.refreshNow()
        XCTAssertEqual(state.nextMeetingURL?.host, "zoom.us", "Once the call ends, the next meeting is up")
    }

    func testNewEventWithLinkCanBeJoined() async throws {
        let (state, _, _) = await StateFixture.make()
        try state.createEvent(
            title: "Catch-up", start: at(10), end: at(10, 30), isAllDay: false, calendarID: "work",
            location: "Studio", url: NewEventDraft.link(from: "zoom.us/j/555"), notes: "Bring sketches"
        )
        XCTAssertEqual(state.nextMeetingURL?.absoluteString, "https://zoom.us/j/555")
        XCTAssertEqual(state.agendaDays.flatMap(\.events).first { $0.title == "Catch-up" }?.location, "Studio")
    }

    func testNewEventLinkParsing() {
        XCTAssertEqual(NewEventDraft.link(from: " https://meet.google.com/abc-defg-hij ")?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(NewEventDraft.link(from: "zoom.us/j/1")?.absoluteString, "https://zoom.us/j/1")
        XCTAssertNil(NewEventDraft.link(from: ""))
        XCTAssertNil(NewEventDraft.link(from: "not a link"))
        XCTAssertNil(NewEventDraft.link(from: "hello"))
        XCTAssertNil(NewEventDraft.link(from: "ftp://files.example.com"))
        XCTAssertNil(NewEventDraft.optional("   "))
    }

    func testCustomVideoServiceAddsJoinLinks() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Team call", start: at(10), minutes: 30), link: "Room: https://call.example.com/r/42")
        }
        XCTAssertNil(state.nextMeetingURL, "Unknown hosts don't get a Join button")

        state.preferences.customVideoServices = [CustomVideoService(name: "Example", host: "call.example.com")]
        state.reload() // Settings reloads after adding or removing a service.
        XCTAssertEqual(state.nextMeetingURL?.host, "call.example.com")

        state.preferences.customVideoServices = []
        state.reload()
        XCTAssertNil(state.nextMeetingURL)
    }

    func testLaunchAtLoginStatusIsReadable() {
        // Registering needs the user's approval in System Settings, so it's checked by hand.
        _ = LaunchAtLogin.isEnabled
    }
}

// MARK: - Display › Menu bar

@MainActor
final class MenuBarSettingsTests: XCTestCase {

    private func state(withEventIn minutes: Double? = nil) async -> AppState {
        await StateFixture.make { store, _ in
            if let minutes {
                store.add(TestSupport.event("Standup", start: now.addingTimeInterval(minutes * 60), minutes: 15))
            }
        }.state
    }

    func testPresetClassic() async {
        let state = await state(withEventIn: 10)
        state.preferences.menuBarFormat.preset = .classic
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47")
    }

    func testPresetMinimal() async {
        let state = await state(withEventIn: 10)
        state.preferences.menuBarFormat.preset = .minimal
        XCTAssertEqual(state.menuBarTitle, "9:47")
    }

    func testPresetAgenda() async {
        let state = await state(withEventIn: 10)
        state.preferences.menuBarFormat.preset = .agenda
        XCTAssertEqual(state.menuBarTitle, "Standup in 10m")
    }

    func testPresetAgendaWithNothingSoon() async {
        let state = await state()
        state.preferences.menuBarFormat.preset = .agenda
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47")
    }

    func testPresetInfo() async {
        let state = await state(withEventIn: 10)
        state.preferences.menuBarFormat.preset = .info
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47 · Standup in 10m")
    }

    func testCustomTokensEachRender() async {
        let state = await state(withEventIn: 10)
        state.preferences.menuBarFormat.preset = .custom
        let expected: [MenuBarToken: String] = [
            .date: "Sat, Oct 31",
            .time: "9:47",
            .nextEvent: "Standup in 10m",
            .weekNumber: "W44",
        ]
        for token in MenuBarToken.allCases {
            state.preferences.menuBarFormat.customTokens = [token]
            XCTAssertEqual(state.menuBarTitle, expected[token], "\(token)")
        }
        state.preferences.menuBarFormat.customTokens = [.weekNumber, .date, .time]
        XCTAssertEqual(state.menuBarTitle, "W44 · Sat, Oct 31 · 9:47", "Tokens keep the order they were added in")
    }

    func testCustomWithNoTokensFallsBackToDateAndTime() async {
        let state = await state()
        state.preferences.menuBarFormat.preset = .custom
        state.preferences.menuBarFormat.customTokens = []
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47")
    }

    func testEveryDateFormatRendersDifferently() async {
        let state = await state()
        state.preferences.menuBarFormat.preset = .classic
        var titles: Set<String> = []
        for pattern in MenuBarFormat.datePatterns {
            state.preferences.menuBarFormat.datePattern = pattern
            let title = state.menuBarTitle
            XCTAssertTrue(title.hasSuffix(" · 9:47"), "\(pattern) → \(title)")
            titles.insert(title)
        }
        XCTAssertEqual(titles.count, MenuBarFormat.datePatterns.count, "Each date format should look different")
    }

    func testTimeFormatAnd24HourClock() async {
        let state = await StateFixture.make(at: at(21, 5)).state
        state.preferences.menuBarFormat.preset = .minimal
        XCTAssertEqual(state.menuBarTitle, "9:05")

        state.preferences.menuBarFormat.setUses24HourTime(true)
        XCTAssertEqual(state.menuBarTitle, "21:05")

        state.preferences.menuBarFormat.setUses24HourTime(false)
        XCTAssertEqual(state.menuBarTitle, "9:05")

        state.preferences.menuBarFormat.timePattern = "h:mm a"
        XCTAssertEqual(state.menuBarTitle, "9:05 PM")
    }

    func testEverySeparator() async {
        let state = await state()
        state.preferences.menuBarFormat.preset = .classic
        let expected: [SeparatorStyle: String] = [
            .bar: "Sat, Oct 31 | 9:47",
            .dot: "Sat, Oct 31 · 9:47",
            .dash: "Sat, Oct 31 — 9:47",
            .space: "Sat, Oct 31  9:47",
        ]
        for separator in SeparatorStyle.allCases {
            state.preferences.menuBarFormat.separator = separator
            XCTAssertEqual(state.menuBarTitle, expected[separator], "\(separator)")
        }
    }

    func testNextEventLeadTime() async {
        let state = await state(withEventIn: 20)
        state.preferences.menuBarFormat.preset = .agenda
        state.preferences.nextEventLeadMinutes = 30
        XCTAssertEqual(state.menuBarTitle, "Standup in 20m")
        state.preferences.nextEventLeadMinutes = 15
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47")
    }
}

// MARK: - Display › Calendar display

@MainActor
final class CalendarDisplaySettingsTests: XCTestCase {

    func testDaySummaryCountsVisibleEvents() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Standup", start: at(9), minutes: 30))
            store.add(TestSupport.event("Lunch", start: at(12), minutes: 60, calendarID: "home"))
            store.add(TestSupport.event("Tomorrow", start: at(9, day: 1, month: 11), minutes: 60))
        }
        XCTAssertEqual(state.daySummary.text, "2 events · 1h 30m busy")
        state.preferences.setCalendar("home", visible: false)
        XCTAssertEqual(state.daySummary.text, "1 event · 30m busy")
    }

    func testShowFreeTime() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Woodworking", start: at(13), minutes: 120))
        }
        let today = try! XCTUnwrap(state.agendaDays.first)
        func freeRows() -> Int {
            state.agendaRows(for: today).filter { if case .free = $0 { true } else { false } }.count
        }
        state.preferences.showFreeTime = false
        XCTAssertEqual(freeRows(), 0)
        state.preferences.showFreeTime = true
        XCTAssertEqual(freeRows(), 2, "9:47–13:00 and 15:00–18:00")
    }

    func testWeekStartsOn() async {
        let (state, _, _) = await StateFixture.make()
        state.preferences.weekStart = .sunday
        XCTAssertEqual(state.calendar.component(.weekday, from: state.gridDays[0].date), 1)
        XCTAssertEqual(state.gridDays[0].date, TestSupport.date(2026, 9, 27))

        state.preferences.weekStart = .monday
        XCTAssertEqual(state.calendar.component(.weekday, from: state.gridDays[0].date), 2)
        XCTAssertEqual(state.gridDays[0].date, TestSupport.date(2026, 9, 28))
    }

    func testEventDotColoursAreDistinctAndCapped() async {
        let colors = [EventColor(red: 1, green: 0, blue: 0), EventColor(red: 0, green: 1, blue: 0),
                      EventColor(red: 0, green: 0, blue: 1), EventColor(red: 1, green: 1, blue: 0)]
        let (state, _, _) = await StateFixture.make { store, _ in
            for (index, color) in (colors + [colors[0]]).enumerated() {
                store.add(CalendarEvent(
                    id: "\(index)", title: "E\(index)", start: at(9 + index), end: at(10 + index), isAllDay: false,
                    calendarID: "work", color: color, location: nil, meetingURL: nil
                ))
            }
        }
        XCTAssertEqual(state.eventColors(on: now), Array(colors.prefix(3)))
        XCTAssertEqual(state.eventColors(on: at(9, day: 1, month: 11)), [])
    }

    func testShowMonthToggle() async {
        let (state, _, _) = await StateFixture.make()
        let initial = state.preferences.showMonthGrid
        state.preferences.showMonthGrid.toggle()
        XCTAssertNotEqual(state.preferences.showMonthGrid, initial)
    }
}

// MARK: - Display › Layout

@MainActor
final class LayoutSettingsTests: XCTestCase {

    func testTextSizeScales() {
        XCTAssertEqual(TextSize.allCases.map(\.scale), [0.9, 1, 1.12, 1.25])
    }

    func testDensityOptionsGrowInOrder() {
        for keyPath in [\Density.dayCellSize, \.gridSpacing, \.eventSpacing, \.sectionSpacing] {
            let values = Density.allCases.map { $0[keyPath: keyPath] }
            XCTAssertEqual(values, values.sorted())
            XCTAssertEqual(Set(values).count, 3)
        }
    }

    func testEveryAgendaLength() async {
        let (state, _, _) = await StateFixture.make()
        state.preferences.hideEmptyDays = false
        for count in Preferences.agendaDayOptions {
            state.preferences.agendaDayCount = count
            XCTAssertEqual(state.agendaDays.count, count, "\(count) days")
        }
    }

    func testAgendaLengthCutsOffLaterEvents() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("In 4 days", start: at(10, day: 4, month: 11), minutes: 30))
            store.add(TestSupport.event("In 25 days", start: at(10, day: 25, month: 11), minutes: 30))
        }
        state.preferences.agendaDayCount = 3
        XCTAssertEqual(state.agendaTitles.flatMap { $0 }, [])
        state.preferences.agendaDayCount = 5
        XCTAssertEqual(state.agendaTitles.flatMap { $0 }, ["In 4 days"])
        state.preferences.agendaDayCount = 30
        XCTAssertEqual(state.agendaTitles.flatMap { $0 }, ["In 4 days", "In 25 days"])
    }

    func testHideEmptyDays() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Dentist", start: at(10, day: 3, month: 11), minutes: 30))
        }
        state.preferences.agendaDayCount = 7
        state.preferences.hideEmptyDays = true
        XCTAssertEqual(state.agendaDays.count, 2, "Today always shows, plus the day with an event")
        state.preferences.hideEmptyDays = false
        XCTAssertEqual(state.agendaDays.count, 7)
    }

    func testHideAllDayEvents() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Halloween", start: TestSupport.date(2026, 10, 31), minutes: 24 * 60, isAllDay: true))
            store.add(TestSupport.event("Standup", start: at(10), minutes: 15))
        }
        XCTAssertEqual(state.agendaTitles.first, ["Halloween", "Standup"])
        state.preferences.hideAllDayEvents = true
        XCTAssertEqual(state.agendaTitles.first, ["Standup"])
        XCTAssertEqual(state.daySummary.eventCount, 1)
        XCTAssertEqual(state.events(on: now).map(\.title), ["Standup"], "Month dots skip all-day events too")
    }

    func testHidePastEvents() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Early run", start: at(6), minutes: 45))
            store.add(TestSupport.event("Breakfast", start: at(8, 30), minutes: 45))
            store.add(TestSupport.event("Focus", start: at(9, 30), minutes: 60))
            store.add(TestSupport.event("Lunch", start: at(12), minutes: 60))
        }
        // Off: today keeps the one event that finished in the last hour (breakfast, done at 9:15), not the run.
        XCTAssertEqual(state.agendaTitles.first, ["Breakfast", "Focus", "Lunch"])
        state.preferences.hidePastEvents = true
        XCTAssertEqual(state.agendaTitles.first, ["Focus", "Lunch"], "Events still in progress stay")
    }
}

// MARK: - Calendars

@MainActor
final class CalendarsSettingsTests: XCTestCase {

    func testDefaultCalendarForNewEvents() async {
        let (state, store, _) = await StateFixture.make { store, _ in
            store.calendarList = [
                StateFixture.calendarInfo("birthdays", source: "Other", writable: false),
                StateFixture.calendarInfo("home"),
                StateFixture.calendarInfo("work"),
            ]
            store.defaultCalendarID = "work"
        }
        XCTAssertEqual(state.writableCalendars.map(\.id), ["home", "work"], "Read-only calendars aren't offered")
        XCTAssertEqual(state.defaultCalendarID, "work", "System default")

        state.preferences.defaultCalendarID = "home"
        XCTAssertEqual(state.defaultCalendarID, "home")
        try? state.createEvent(title: "Dinner", start: at(19), end: at(20), isAllDay: false, calendarID: state.defaultCalendarID!)
        XCTAssertEqual(store.created.last?.calendarID, "home")

        state.preferences.defaultCalendarID = "birthdays"
        XCTAssertEqual(state.defaultCalendarID, "work", "A read-only choice falls back to the system default")

        state.preferences.defaultCalendarID = "deleted"
        store.defaultCalendarID = nil
        state.reload()
        XCTAssertEqual(state.defaultCalendarID, "home", "With no usable default, the first writable calendar")
    }

    func testIgnoreTitlesContaining() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Daycare pickup", start: at(10), minutes: 15))
            store.add(TestSupport.event("Standup", start: at(10, 30), minutes: 15))
        }
        state.preferences.menuBarFormat.preset = .agenda
        state.preferences.nextEventLeadMinutes = 60
        state.preferences.ignoredTitleKeywords = "daycare, school run"

        XCTAssertEqual(state.agendaTitles.first, ["Standup"])
        XCTAssertEqual(state.menuBarTitle, "Standup in 43m")
        XCTAssertEqual(state.events(on: now).map(\.title), ["Standup"])
        state.beginSearch()
        state.searchQuery = "pickup"
        XCTAssertEqual(state.searchResults, [])

        state.preferences.ignoredTitleKeywords = ""
        XCTAssertEqual(state.agendaTitles.first, ["Daycare pickup", "Standup"])
    }

    func testMapsProviderLinks() {
        XCTAssertEqual(MapsProvider.apple.url(for: "Ronald Reagan Washington National")?.host, "maps.apple.com")
        XCTAssertEqual(MapsProvider.google.url(for: "Ronald Reagan Washington National")?.host, "www.google.com")
    }

    func testCalendarToggles() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Standup", start: at(10), minutes: 15, calendarID: "work"))
            store.add(TestSupport.event("Gym", start: at(11), minutes: 60, calendarID: "home"))
        }
        state.preferences.menuBarFormat.preset = .agenda

        state.preferences.setCalendar("work", visible: false)
        XCTAssertEqual(state.agendaTitles.first, ["Gym"])
        XCTAssertEqual(state.events(on: now).map(\.title), ["Gym"])
        XCTAssertEqual(state.menuBarTitle, "Sat, Oct 31 · 9:47", "Hidden calendar's event isn't announced")

        state.preferences.setCalendar("work", visible: true)
        XCTAssertEqual(state.agendaTitles.first, ["Standup", "Gym"])
    }

    func testAllAndNoneButtons() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Standup", start: at(10), minutes: 15))
        }
        state.preferences.hideAllCalendars(state.calendars.map(\.id))
        XCTAssertTrue(state.calendars.allSatisfy { !state.preferences.isCalendarVisible($0.id) })
        XCTAssertEqual(state.agendaTitles.first, [])

        state.preferences.showAllCalendars()
        XCTAssertTrue(state.calendars.allSatisfy { state.preferences.isCalendarVisible($0.id) })
        XCTAssertEqual(state.agendaTitles.first, ["Standup"])
    }
}

// MARK: - Persistence

/// Every setting, in every option, survives a relaunch.
@MainActor
final class SettingsPersistenceTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "OrbitPersistence-\(UUID().uuidString)")
    }

    private func reloaded() -> Preferences { Preferences(defaults: defaults) }

    func testDefaults() {
        let preferences = reloaded()
        XCTAssertFalse(preferences.keepCalendarOnTop)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertTrue(preferences.globalShortcutsEnabled)
        XCTAssertEqual(preferences.menuBarFormat, MenuBarFormat())
        XCTAssertEqual(preferences.nextEventLeadMinutes, 30)
        XCTAssertTrue(preferences.showYearProgress)
        XCTAssertTrue(preferences.highlightToday)
        XCTAssertTrue(preferences.showMonthGrid)
        XCTAssertEqual(preferences.eventDots, .colors)
        XCTAssertEqual(preferences.textSize, .standard)
        XCTAssertEqual(preferences.agendaDayCount, 14)
        XCTAssertTrue(preferences.hideEmptyDays)
        XCTAssertEqual(preferences.mapsProvider, .apple)
        XCTAssertNil(preferences.defaultCalendarID)
    }

    func testBooleans() {
        let keyPaths: [ReferenceWritableKeyPath<Preferences, Bool>] = [
            \.keepCalendarOnTop, \.globalShortcutsEnabled, \.showDaySummary, \.showFreeTime, \.showYearProgress,
            \.showDayProgress, \.showWeekNumbers, \.highlightToday, \.dimWeekends, \.showMonthGrid,
            \.hideEmptyDays, \.hideAllDayEvents, \.hidePastEvents,
        ]
        for keyPath in keyPaths {
            for value in [true, false] {
                reloaded()[keyPath: keyPath] = value
                XCTAssertEqual(reloaded()[keyPath: keyPath], value, "\(keyPath) = \(value)")
            }
        }
    }

    func testEveryOptionOfEveryPicker() {
        for value in AppearanceMode.allCases { reloaded().appearance = value; XCTAssertEqual(reloaded().appearance, value) }
        for value in EventDotsStyle.allCases { reloaded().eventDots = value; XCTAssertEqual(reloaded().eventDots, value) }
        for value in WeekStart.allCases { reloaded().weekStart = value; XCTAssertEqual(reloaded().weekStart, value) }
        for value in TextSize.allCases { reloaded().textSize = value; XCTAssertEqual(reloaded().textSize, value) }
        for value in Density.allCases {
            reloaded().calendarDensity = value; XCTAssertEqual(reloaded().calendarDensity, value)
            reloaded().eventDensity = value; XCTAssertEqual(reloaded().eventDensity, value)
        }
        for value in MapsProvider.allCases { reloaded().mapsProvider = value; XCTAssertEqual(reloaded().mapsProvider, value) }
        for value in Preferences.agendaDayOptions { reloaded().agendaDayCount = value; XCTAssertEqual(reloaded().agendaDayCount, value) }
        for value in [5, 30, 120] { reloaded().nextEventLeadMinutes = value; XCTAssertEqual(reloaded().nextEventLeadMinutes, value) }
    }

    func testMenuBarFormat() {
        for preset in MenuBarPreset.allCases {
            var format = MenuBarFormat()
            format.preset = preset
            format.customTokens = [.weekNumber, .nextEvent]
            format.separator = SeparatorStyle.allCases.randomElement()!
            format.datePattern = MenuBarFormat.datePatterns.randomElement()!
            format.setUses24HourTime(true)
            reloaded().menuBarFormat = format
            XCTAssertEqual(reloaded().menuBarFormat, format, "\(preset)")
        }
    }

    func testCalendarsTab() {
        reloaded().defaultCalendarID = "home"
        reloaded().ignoredTitleKeywords = "daycare, school run"
        reloaded().setCalendar("work", visible: false)
        reloaded().customVideoServices = [CustomVideoService(name: "Example", host: "call.example.com")]

        let preferences = reloaded()
        XCTAssertEqual(preferences.defaultCalendarID, "home")
        XCTAssertEqual(preferences.ignoredTitleKeywords, "daycare, school run")
        XCTAssertFalse(preferences.isCalendarVisible("work"))
        XCTAssertEqual(preferences.customMeetingHosts, ["call.example.com"])

        preferences.defaultCalendarID = nil
        XCTAssertNil(reloaded().defaultCalendarID, "Back to System default")
    }
}
