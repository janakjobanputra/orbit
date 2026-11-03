import XCTest
@testable import Orbit

final class EventTimingTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        TestSupport.date(2026, 11, 1, hour, minute, second)
    }

    private let call = TestSupport.event("Call", start: TestSupport.date(2026, 11, 1, 19, 40), minutes: 30)

    func testStatesThroughAnEvent() {
        XCTAssertEqual(EventTiming(event: call, now: at(19, 29)), .later)
        XCTAssertEqual(EventTiming(event: call, now: at(19, 30)), .soon(startsIn: 600))
        XCTAssertEqual(EventTiming(event: call, now: at(19, 40)), .now(remaining: 1800))
        XCTAssertEqual(EventTiming(event: call, now: at(20, 9, 59)), .now(remaining: 1))
        XCTAssertEqual(EventTiming(event: call, now: at(20, 10)), .ended)
    }

    func testLabels() {
        XCTAssertNil(EventTiming(event: call, now: at(19)).label)
        XCTAssertEqual(EventTiming(event: call, now: at(19, 34)).label, "in 6m")
        XCTAssertEqual(EventTiming(event: call, now: at(19, 39, 30)).label, "in 1m", "Never says in 0m")
        XCTAssertEqual(EventTiming(event: call, now: at(19, 42)).label, "28m left")
        XCTAssertEqual(EventTiming(event: call, now: at(20, 9, 50)).label, "1m left")
        XCTAssertEqual(EventTiming(event: call, now: at(21)).label, "Ended")
        let long = TestSupport.event("Workshop", start: at(9), minutes: 180)
        XCTAssertEqual(EventTiming(event: long, now: at(9, 30)).label, "2h 30m left")
    }

    func testOnlyNowAndSoonAreHighlighted() {
        XCTAssertFalse(EventTiming.isHighlighted(call, now: at(19, 29)))
        XCTAssertTrue(EventTiming.isHighlighted(call, now: at(19, 30)))
        XCTAssertTrue(EventTiming.isHighlighted(call, now: at(20, 9)))
        XCTAssertFalse(EventTiming.isHighlighted(call, now: at(20, 10)))
        let allDay = TestSupport.event("Holiday", start: TestSupport.date(2026, 11, 1), minutes: 24 * 60, isAllDay: true)
        XCTAssertFalse(EventTiming.isHighlighted(allDay, now: at(12)))
    }
}

final class EventDetailsTests: XCTestCase {

    func testOtherLinksSkipMeetingsBoilerplateAndDuplicates() {
        let notes = """
        Join: https://meet.google.com/abc-defg-hij
        Agenda https://docs.google.com/document/d/1 and again https://docs.google.com/document/d/1
        Learn more about Meet at: https://support.google.com/a/users/answer/9282720
        Slides: https://www.figma.com/file/xyz
        """
        let links = MeetingLinkDetector.otherLinks(in: [nil, "Studio", notes])
        XCTAssertEqual(links.map(\.absoluteString), ["https://docs.google.com/document/d/1", "https://www.figma.com/file/xyz"])
        XCTAssertEqual(LinkText.host(links[1]), "figma.com")
    }

    func testNotesFromHTML() {
        let html = #"Agenda<br>Bring <b>sketches</b> &amp; notes<br><br><br><a href="https://docs.google.com/x">Doc</a><br><a href="https://example.com">https://example.com</a>"#
        XCTAssertEqual(NotesText.plain(html), "Agenda\nBring sketches & notes\n\nDoc (https://docs.google.com/x)\nhttps://example.com")
        XCTAssertEqual(NotesText.plain("Plain notes, 2 < 3"), "Plain notes, 2 < 3")
        XCTAssertNil(NotesText.plain("   \n "))
        XCTAssertNil(NotesText.plain(nil))
    }

    func testNotesLinksAreClickable() {
        let attributed = NotesLinks.attributed("See https://example.com/a for details")
        let links = attributed.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "https://example.com/a")!])
    }

    func testGuestSummary() {
        XCTAssertNil(GuestSummary.text([]))
        let guests = [
            Guest(name: "Ana", response: .accepted, isOrganizer: true),
            Guest(name: "Ben", response: .accepted),
            Guest(name: "Cy", response: .tentative),
        ]
        XCTAssertEqual(GuestSummary.text(guests), "3 guests · 2 yes, 1 maybe")
        XCTAssertEqual(GuestSummary.text([Guest(name: "Di", response: .pending)]), "1 guest · 1 awaiting")
    }

    func testCopyText() {
        var event = TestSupport.event("Catch-up", start: TestSupport.date(2026, 11, 1, 19, 40), minutes: 30)
        event.meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")
        let text = EventCopyText.make(event, calendar: TestSupport.calendar())
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Catch-up")
        XCTAssertTrue(lines[1].contains("November 1, 2026"), lines[1])
        XCTAssertTrue(lines[1].contains("7:40"), lines[1])
        XCTAssertEqual(lines.last, "Join: https://meet.google.com/abc-defg-hij")
    }
}

@MainActor
final class EventActionsTests: XCTestCase {

    func testDeleteOnlyOnWritableCalendars() async throws {
        let (state, store, _) = await StateFixture.make { store, _ in
            store.calendarList = [StateFixture.calendarInfo("work"), StateFixture.calendarInfo("birthdays", writable: false)]
            var mine = TestSupport.event("Mine", start: StateFixture.now.addingTimeInterval(3600), minutes: 30)
            mine.calendarItemID = "mine"
            var birthday = TestSupport.event("Birthday", start: StateFixture.now.addingTimeInterval(3600), minutes: 30, calendarID: "birthdays")
            birthday.calendarItemID = "bday"
            store.add(mine)
            store.add(birthday)
        }
        let events = state.agendaDays.flatMap(\.events)
        let mine = try XCTUnwrap(events.first { $0.title == "Mine" })
        let birthday = try XCTUnwrap(events.first { $0.title == "Birthday" })
        XCTAssertTrue(state.canDelete(mine))
        XCTAssertFalse(state.canDelete(birthday))

        try state.deleteEvent(mine)
        XCTAssertFalse(state.agendaDays.flatMap(\.events).contains { $0.title == "Mine" })
        XCTAssertEqual(store.stored.count, 1)
    }

    func testCalendarNameForEvent() async {
        let (state, _, _) = await StateFixture.make()
        let event = TestSupport.event("x", start: StateFixture.now, minutes: 30)
        XCTAssertEqual(state.calendarInfo(for: event)?.title, "Work")
    }
}

final class FinishedEventsTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date { TestSupport.date(2026, 11, 1, hour, minute) }

    private var day: [CalendarEvent] {
        [
            TestSupport.event("DST ends", start: TestSupport.date(2026, 11, 1), minutes: 24 * 60, isAllDay: true),
            TestSupport.event("Match", start: at(11, 30), minutes: 120),
            TestSupport.event("Flight", start: at(18, 6), minutes: 144),
            TestSupport.event("Test event", start: at(19, 40), minutes: 30),
            TestSupport.event("Late flight", start: at(22, 35), minutes: 130),
        ]
    }

    func testKeepsOnlyTheLatestEventFinishedWithinAnHour() {
        // At 20:15 the match (13:30) is long over; the test event finished 5 minutes ago and the flight is on.
        let titles = Agenda.withoutFinished(day, now: at(20, 15)).map(\.title)
        XCTAssertEqual(titles, ["DST ends", "Flight", "Test event", "Late flight"])
        // At 21:00 the flight (20:30) is the most recent finish, so the test event goes.
        XCTAssertEqual(Agenda.withoutFinished(day, now: at(21)).map(\.title), ["DST ends", "Flight", "Late flight"])
    }

    func testDropsEverythingFinishedMoreThanAnHourAgo() {
        let titles = Agenda.withoutFinished(day, now: at(21, 31)).map(\.title)
        XCTAssertEqual(titles, ["DST ends", "Late flight"], "All-day stays; the next upcoming event is first")
    }

    func testInProgressEventsAlwaysStay() {
        let titles = Agenda.withoutFinished(day, now: at(19, 45)).map(\.title)
        XCTAssertEqual(titles, ["DST ends", "Flight", "Test event", "Late flight"], "The match ended over an hour ago")
    }

    func testOnlyOneRecentEventEvenWhenSeveralJustEnded() {
        let events = [
            TestSupport.event("A", start: at(9), minutes: 30),
            TestSupport.event("B", start: at(9), minutes: 45),
            TestSupport.event("C", start: at(11), minutes: 30),
        ]
        XCTAssertEqual(Agenda.withoutFinished(events, now: at(10)).map(\.title), ["B", "C"])
    }
}

@MainActor
final class PopoverEscapeTests: XCTestCase {

    func testEscapeClosesDetailBeforePopover() async {
        let (state, _, _) = await StateFixture.make()
        state.detailEventID = "call"
        XCTAssertTrue(state.handleEscape(), "First Escape closes the detail")
        XCTAssertNil(state.detailEventID)
        XCTAssertFalse(state.handleEscape(), "Second Escape is left for the popover to close")
    }

    func testOnlyTodayIsTrimmed() async {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(TestSupport.event("Breakfast", start: TestSupport.date(2026, 10, 31, 7), minutes: 30))
            store.add(TestSupport.event("Gym", start: TestSupport.date(2026, 10, 31, 9), minutes: 30))
            store.add(TestSupport.event("Lunch", start: TestSupport.date(2026, 10, 31, 12), minutes: 60))
        }
        // 9:47: breakfast ended over an hour ago, the gym 17 minutes ago.
        XCTAssertEqual(state.agendaDays.first?.events.map(\.title), ["Gym", "Lunch"])
        // Other days still list everything.
        state.selectedDate = TestSupport.date(2026, 10, 30)
        XCTAssertEqual(state.agendaDays.first { $0.kind == .today }?.events.map(\.title), ["Gym", "Lunch"])
    }
}

@MainActor
final class DemoEventStoreTests: XCTestCase {

    func testDemoCoversEveryFeature() async {
        let now = TestSupport.date(2026, 11, 2, 9, 13)
        let calendar = TestSupport.calendar()
        let defaults = UserDefaults(suiteName: "OrbitDemoTests-\(UUID().uuidString)")!
        let state = AppState(preferences: Preferences(defaults: defaults), eventService: DemoEventStore(now: now, calendar: calendar), calendar: calendar) { now }
        await state.start()
        state.stop()

        let today = state.agendaDays.first { $0.kind == .today }
        let events = today?.events ?? []
        XCTAssertGreaterThanOrEqual(events.filter(\.isAllDay).count, 2, "All-day events for the pinned header")
        XCTAssertTrue(events.contains { EventTiming(event: $0, now: now) == .now(remaining: $0.end.timeIntervalSince(now)) && $0.meetingURL != nil && !$0.links.isEmpty && $0.location != nil },
                      "A meeting in progress with Join, Map and a link")
        XCTAssertEqual(events.filter { !$0.isAllDay && $0.end <= now }.count, 1, "Exactly one recently finished event is kept")
        XCTAssertNotNil(state.nextMeetingURL)
        XCTAssertGreaterThanOrEqual(Set(state.calendars.map(\.id)).count, 4)
        XCTAssertTrue(state.calendars.contains { !$0.isWritable }, "A read-only calendar, so Delete can be seen missing")

        let daysWithDots = state.gridDays.filter { $0.isInDisplayedMonth && !state.eventColors(on: $0.date).isEmpty }
        XCTAssertGreaterThanOrEqual(daysWithDots.count, 12)
        XCTAssertTrue(state.gridDays.contains { state.eventColors(on: $0.date).count >= 2 }, "Some days show several colors")
        XCTAssertTrue(state.agendaDays.contains { day in day.events.contains { !$0.isAllDay && !calendar.isDate($0.start, inSameDayAs: $0.end) } },
                      "An overnight event")
    }
}
