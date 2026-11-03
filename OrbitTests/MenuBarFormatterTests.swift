import XCTest
@testable import Orbit

final class MenuBarFormatterTests: XCTestCase {

    private let now = TestSupport.date(2026, 10, 31, 9, 47)

    private func formatter(_ preset: MenuBarPreset = .classic, configure: (inout MenuBarFormat) -> Void = { _ in }) -> MenuBarFormatter {
        var format = MenuBarFormat()
        format.preset = preset
        configure(&format)
        return MenuBarFormatter(format: format, leadMinutes: 30, locale: Locale(identifier: "en_US"), calendar: TestSupport.calendar())
    }

    private func standup(inMinutes minutes: Double) -> CalendarEvent {
        TestSupport.event("Standup", start: now.addingTimeInterval(minutes * 60), minutes: 15)
    }

    func testIconStyleShowsNoText() {
        let icon = formatter(.icon) { $0.timePattern = "h:mm:ss" }
        XCTAssertEqual(icon.title(now: now, events: [standup(inMinutes: 5)]), "")
        XCTAssertTrue(icon.format.isIconOnly)
        XCTAssertFalse(icon.format.showsSeconds, "Nothing ticks when only the logo shows")
        XCTAssertFalse(formatter(.classic).format.isIconOnly)
    }

    func testClassicShowsDateAndTime() {
        XCTAssertEqual(formatter(.classic).title(now: now, events: []), "Sat, Oct 31 · 9:47")
    }

    func testMinimalShowsTimeOnly() {
        XCTAssertEqual(formatter(.minimal).title(now: now, events: []), "9:47")
    }

    func testAgendaShowsUpcomingEvent() {
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [standup(inMinutes: 10)]), "Standup in 10m")
    }

    func testAgendaFallsBackToDateAndTimeWithNothingUpcoming() {
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [standup(inMinutes: 45)]), "Sat, Oct 31 · 9:47")
    }

    func testInfoAddsEventAfterDateAndTime() {
        XCTAssertEqual(formatter(.info).title(now: now, events: [standup(inMinutes: 10)]), "Sat, Oct 31 · 9:47 · Standup in 10m")
    }

    func testInfoOmitsEventWhenNoneIsClose() {
        XCTAssertEqual(formatter(.info).title(now: now, events: []), "Sat, Oct 31 · 9:47")
    }

    func testCustomTokensAndSeparator() {
        let title = formatter(.custom) {
            $0.customTokens = [.weekNumber, .time]
            $0.separator = .bar
        }.title(now: now, events: [])
        XCTAssertEqual(title, "W44 | 9:47")
    }

    func testCustomDateAndTimePatterns() {
        let title = formatter(.classic) {
            $0.datePattern = "d MMM"
            $0.timePattern = "HH:mm"
            $0.separator = .space
        }.title(now: now, events: [])
        XCTAssertEqual(title, "31 Oct  09:47")
    }

    func testEmptyPatternsFallBackToDefaults() {
        let title = formatter(.classic) {
            $0.datePattern = " "
            $0.timePattern = ""
        }.title(now: now, events: [])
        XCTAssertEqual(title, "Sat, Oct 31 · 9:47")
    }

    func testShowsTimeLeftForEventInProgress() {
        let focus = TestSupport.event("Focus", start: now.addingTimeInterval(-10 * 60), minutes: 30)
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [focus]), "Focus · 20m left")
    }

    func testUpcomingEventWinsOverEventInProgress() {
        let focus = TestSupport.event("Focus", start: now.addingTimeInterval(-60 * 60), minutes: 180)
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [focus, standup(inMinutes: 5)]), "Standup in 5m")
    }

    func testIgnoresAllDayEvents() {
        let holiday = TestSupport.event("Holiday", start: TestSupport.date(2026, 10, 31), minutes: 24 * 60, isAllDay: true)
        XCTAssertNil(formatter().eventText(now: now, events: [holiday]))
    }

    func testRoundsPartialMinutesUp() {
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [standup(inMinutes: 9.5)]), "Standup in 10m")
    }

    func testTruncatesLongTitles() {
        let event = TestSupport.event("Quarterly planning with the whole product team", start: now.addingTimeInterval(5 * 60), minutes: 60)
        XCTAssertEqual(formatter(.agenda).title(now: now, events: [event]), "Quarterly planning with… in 5m")
    }
}

final class MenuBarFormatTests: XCTestCase {

    func testSwitchesTo24HourClock() {
        var format = MenuBarFormat()
        format.timePattern = "h:mm a"
        format.setUses24HourTime(true)
        XCTAssertEqual(format.timePattern, "H:mm")
        XCTAssertTrue(format.uses24HourTime)
    }

    func testSwitchesBackTo12HourClock() {
        var format = MenuBarFormat()
        format.timePattern = "HH:mm"
        format.setUses24HourTime(false)
        XCTAssertEqual(format.timePattern, "hh:mm")
        XCTAssertFalse(format.uses24HourTime)
    }

    func testIconStyleRoundTripsThroughJSON() throws {
        var format = MenuBarFormat()
        format.preset = .icon
        XCTAssertEqual(try JSONDecoder().decode(MenuBarFormat.self, from: JSONEncoder().encode(format)).preset, .icon)
    }

    func testPresetsChooseTokens() {
        var format = MenuBarFormat()
        format.customTokens = [.weekNumber]
        format.preset = .info
        XCTAssertEqual(format.tokens, [.date, .time, .nextEvent])
        format.preset = .custom
        XCTAssertEqual(format.tokens, [.weekNumber])
    }

    func testRoundTripsThroughJSON() throws {
        var format = MenuBarFormat()
        format.preset = .custom
        format.customTokens = [.time, .nextEvent]
        format.separator = .dash
        let decoded = try JSONDecoder().decode(MenuBarFormat.self, from: JSONEncoder().encode(format))
        XCTAssertEqual(decoded, format)
    }
}
