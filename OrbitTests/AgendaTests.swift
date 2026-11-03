import XCTest
@testable import Orbit

final class AgendaTests: XCTestCase {

    private let calendar = TestSupport.calendar()
    private let now = TestSupport.date(2026, 10, 31, 9, 18)

    func testLabelsTodayAndTomorrowAndSkipsEmptyDays() {
        let events = [
            TestSupport.event("Woodworking", start: TestSupport.date(2026, 10, 31, 13), minutes: 240),
            TestSupport.event("Football", start: TestSupport.date(2026, 11, 1, 11, 30), minutes: 120),
            TestSupport.event("Dentist", start: TestSupport.date(2026, 11, 4, 10), minutes: 30),
        ]
        let days = Agenda.days(from: now, count: 14, events: events, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.kind), [.today, .tomorrow, .other])
        XCTAssertEqual(days.last?.date, TestSupport.date(2026, 11, 4))
    }

    func testFirstDayAppearsEvenWhenEmpty() {
        let days = Agenda.days(from: now, count: 7, events: [], now: now, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.kind, .today)
        XCTAssertEqual(days.first?.events, [])
    }

    func testStopsAfterCount() {
        let late = TestSupport.event("Later", start: TestSupport.date(2026, 11, 20, 10), minutes: 30)
        let days = Agenda.days(from: now, count: 14, events: [late], now: now, calendar: calendar)
        XCTAssertEqual(days.count, 1)
    }

    func testAllDayEventsSortFirst() {
        let timed = TestSupport.event("Breakfast", start: TestSupport.date(2026, 10, 31, 8), minutes: 30)
        let allDay = TestSupport.event("Halloween", start: TestSupport.date(2026, 10, 31), minutes: 24 * 60, isAllDay: true)
        XCTAssertEqual(Agenda.sorted([timed, allDay]).map(\.title), ["Halloween", "Breakfast"])
    }

    func testIncludesEmptyDaysWhenAsked() {
        let late = TestSupport.event("Dentist", start: TestSupport.date(2026, 11, 2, 10), minutes: 30)
        let days = Agenda.days(from: now, count: 3, events: [late], now: now, calendar: calendar, includeEmptyDays: true)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[1].events, [])
    }

    func testNowLineSitsAboveFirstUpcomingEvent() {
        let rows = Agenda.rows(events: [
            TestSupport.event("Woodworking", start: TestSupport.date(2026, 10, 31, 13), minutes: 240),
            TestSupport.event("Halloween", start: TestSupport.date(2026, 10, 31), minutes: 24 * 60, isAllDay: true),
            TestSupport.event("Breakfast", start: TestSupport.date(2026, 10, 31, 8), minutes: 30),
        ], gaps: [], now: now)
        XCTAssertEqual(rows.map(label), ["Halloween", "Breakfast", "now", "Woodworking"])
    }

    func testNowLineGoesAboveEventInProgress() {
        let rows = Agenda.rows(events: [
            TestSupport.event("Breakfast", start: TestSupport.date(2026, 10, 31, 8), minutes: 30),
            TestSupport.event("Focus", start: TestSupport.date(2026, 10, 31, 9), minutes: 60),
        ], gaps: [], now: now)
        XCTAssertEqual(rows.map(label), ["Breakfast", "now", "Focus"], "Focus runs until 10:00, so it hasn't passed at 9:47")
    }

    func testEventDropsBelowNowLineOnlyWhenItEnds() {
        let call = TestSupport.event("Call", start: TestSupport.date(2026, 10, 31, 19, 30), minutes: 30)
        let at = { (minute: Int) in TestSupport.date(2026, 10, 31, 19, minute) }
        XCTAssertEqual(Agenda.rows(events: [call], gaps: [], now: at(45)).map(label), ["now", "Call"])
        XCTAssertEqual(Agenda.rows(events: [call], gaps: [], now: at(59)).map(label), ["now", "Call"])
        XCTAssertEqual(Agenda.rows(events: [call], gaps: [], now: TestSupport.date(2026, 10, 31, 20)).map(label), ["Call", "now"])
    }

    func testNoNowLineOnOtherDays() {
        let rows = Agenda.rows(events: [TestSupport.event("Focus", start: TestSupport.date(2026, 11, 1, 9), minutes: 60)], gaps: [], now: nil)
        XCTAssertEqual(rows.map(label), ["Focus"])
    }

    func testFreeGapsInterleaveByTimeAndSitBelowNowLine() {
        let gaps = [
            FreeGap(start: now, end: TestSupport.date(2026, 10, 31, 13)),
            FreeGap(start: TestSupport.date(2026, 10, 31, 17), end: TestSupport.date(2026, 10, 31, 18)),
        ]
        let rows = Agenda.rows(
            events: [TestSupport.event("Woodworking", start: TestSupport.date(2026, 10, 31, 13), minutes: 240)],
            gaps: gaps,
            now: now
        )
        XCTAssertEqual(rows.map(label), ["now", "free 9:18", "Woodworking", "free 17:00"])
    }

    private func label(_ row: AgendaRow) -> String {
        switch row {
        case .event(let event): event.title
        case .now: "now"
        case .free(let gap):
            "free \(calendar.component(.hour, from: gap.start)):\(String(format: "%02d", calendar.component(.minute, from: gap.start)))"
        }
    }

    func testRemovesDuplicatesFromDifferentCalendars() {
        let start = TestSupport.date(2026, 10, 31)
        let events = [
            TestSupport.event("Birthday", start: start, minutes: 24 * 60, isAllDay: true, calendarID: "contacts"),
            TestSupport.event("Birthday", start: start, minutes: 24 * 60, isAllDay: true, calendarID: "family"),
            TestSupport.event("Birthday", start: start.addingTimeInterval(86_400), minutes: 24 * 60, isAllDay: true),
        ]
        let unique = Agenda.deduplicated(events)
        XCTAssertEqual(unique.count, 2)
        XCTAssertEqual(unique.first?.calendarID, "contacts")
    }
}

final class YearProgressTests: XCTestCase {

    private let calendar = TestSupport.calendar()

    func testHalloween2026() {
        let progress = YearProgress(date: TestSupport.date(2026, 10, 31, 9, 18), calendar: calendar)
        XCTAssertEqual(progress.year, 2026)
        XCTAssertEqual(progress.daysLeft, 61)
        XCTAssertEqual(progress.fraction, 0.831, accuracy: 0.0005)
    }

    func testLastDayOfYearHasNoDaysLeft() {
        let progress = YearProgress(date: TestSupport.date(2026, 12, 31, 12), calendar: calendar)
        XCTAssertEqual(progress.daysLeft, 0)
    }

    func testStartOfYearIsZero() {
        let progress = YearProgress(date: TestSupport.date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.daysLeft, 364)
        XCTAssertEqual(progress.elapsedText, "0.0% of 2026")
        XCTAssertEqual(progress.remainingText, "364 days left")
    }

    func testLabelsAcrossTheYear() {
        let halloween = YearProgress(date: TestSupport.date(2026, 10, 31, 9, 18), calendar: calendar)
        XCTAssertEqual(halloween.elapsedText, "83.1% of 2026")
        XCTAssertEqual(halloween.remainingText, "61 days left")

        let secondToLast = YearProgress(date: TestSupport.date(2026, 12, 30, 12), calendar: calendar)
        XCTAssertEqual(secondToLast.remainingText, "1 day left")

        let lastDay = YearProgress(date: TestSupport.date(2026, 12, 31, 0, 1), calendar: calendar)
        XCTAssertEqual(lastDay.remainingText, "Last day")

        // A minute before midnight is 99.99…%, which must not round up to 100%.
        let lastMinute = YearProgress(date: TestSupport.date(2026, 12, 31, 23, 59), calendar: calendar)
        XCTAssertEqual(lastMinute.elapsedText, "99.9% of 2026")
        XCTAssertEqual(lastMinute.remainingText, "Last day")
    }

    func testLeapYear() {
        let progress = YearProgress(date: TestSupport.date(2028, 1, 1), calendar: calendar)
        XCTAssertEqual(progress.daysLeft, 365)
        let midYear = YearProgress(date: TestSupport.date(2028, 7, 2), calendar: calendar)
        XCTAssertEqual(midYear.fraction, 183.0 / 366, accuracy: 0.0001)
        XCTAssertEqual(midYear.elapsedText, "50.0% of 2028")
    }

    func testPercentNeverRoundsUpToFull() {
        XCTAssertEqual(ProgressText.percent(0), "0.0%")
        XCTAssertEqual(ProgressText.percent(0.0004), "0.0%")
        XCTAssertEqual(ProgressText.percent(0.5), "50.0%")
        XCTAssertEqual(ProgressText.percent(0.99999), "99.9%")
        XCTAssertEqual(ProgressText.percent(1), "100.0%")
        XCTAssertEqual(ProgressText.percent(-0.2), "0.0%")
        XCTAssertEqual(ProgressText.percent(1.3), "100.0%")
    }
}

final class EventSearchTests: XCTestCase {

    private let now = TestSupport.date(2026, 10, 31, 9)

    func testMatchesAllWordsIgnoringCaseAndAccents() {
        let events = [
            TestSupport.event("Café with Priya", start: now, minutes: 30),
            TestSupport.event("Cafe planning", start: now, minutes: 30),
        ]
        XCTAssertEqual(EventSearch.matches(events, query: "cafe priya").map(\.title), ["Café with Priya"])
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertEqual(EventSearch.matches([TestSupport.event("Standup", start: now, minutes: 15)], query: "  "), [])
    }

    func testRanksUpcomingBeforePast() {
        let past = TestSupport.event("Old", start: now.addingTimeInterval(-86_400), minutes: 30)
        let older = TestSupport.event("Older", start: now.addingTimeInterval(-2 * 86_400), minutes: 30)
        let soon = TestSupport.event("Soon", start: now.addingTimeInterval(3600), minutes: 30)
        let later = TestSupport.event("Later", start: now.addingTimeInterval(86_400), minutes: 30)
        XCTAssertEqual(EventSearch.ranked([older, later, past, soon], now: now).map(\.title), ["Soon", "Later", "Old", "Older"])
    }
}

final class NewEventDraftTests: XCTestCase {

    private let calendar = TestSupport.calendar()

    func testTodayStartsAtNextHalfHour() {
        let now = TestSupport.date(2026, 10, 31, 9, 18)
        XCTAssertEqual(NewEventDraft.defaultStart(on: now, now: now, calendar: calendar), TestSupport.date(2026, 10, 31, 9, 30))
    }

    func testTodayAfterHalfPastStartsAtNextHour() {
        let now = TestSupport.date(2026, 10, 31, 9, 45)
        XCTAssertEqual(NewEventDraft.defaultStart(on: now, now: now, calendar: calendar), TestSupport.date(2026, 10, 31, 10))
    }

    func testOtherDaysStartAtNine() {
        let now = TestSupport.date(2026, 10, 31, 9, 18)
        XCTAssertEqual(
            NewEventDraft.defaultStart(on: TestSupport.date(2026, 11, 3), now: now, calendar: calendar),
            TestSupport.date(2026, 11, 3, 9)
        )
    }

    func testRequiresTitleAndOrderedTimes() {
        let start = TestSupport.date(2026, 10, 31, 9)
        XCTAssertTrue(NewEventDraft.isValid(title: "Lunch", start: start, end: start))
        XCTAssertFalse(NewEventDraft.isValid(title: "  ", start: start, end: start))
        XCTAssertFalse(NewEventDraft.isValid(title: "Lunch", start: start, end: start.addingTimeInterval(-60)))
    }
}
