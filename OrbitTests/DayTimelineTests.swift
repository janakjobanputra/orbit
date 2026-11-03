import XCTest
@testable import Orbit

final class DayTimelineTests: XCTestCase {

    private let day = TestSupport.date(2026, 11, 2)

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        TestSupport.date(2026, 11, day, hour, minute)
    }

    private func timeline(_ events: [CalendarEvent]) -> DayTimeline {
        DayTimeline(events: events, day: day, calendar: TestSupport.calendar())
    }

    private func block(_ timeline: DayTimeline, _ title: String) -> DayTimeline.Block? {
        timeline.blocks.first { $0.event.title == title }
    }

    func testAllDayEventsGoOnTopAndTimedOnesOnTheTimeline() {
        let holiday = TestSupport.event("Holiday", start: day, minutes: 24 * 60, isAllDay: true)
        let gym = TestSupport.event("Gym", start: at(7, 10), minutes: 80)
        let t = timeline([gym, holiday])
        XCTAssertEqual(t.allDay.map(\.title), ["Holiday"])
        XCTAssertEqual(t.blocks.map(\.event.title), ["Gym"])
        XCTAssertEqual(block(t, "Gym")?.startMinute, 7 * 60 + 10)
        XCTAssertEqual(block(t, "Gym")?.endMinute, 8 * 60 + 30)
    }

    func testOtherDaysAreLeftOut() {
        let yesterday = TestSupport.event("Yesterday", start: at(10, day: 1), minutes: 60)
        let tomorrow = TestSupport.event("Tomorrow", start: at(10, day: 3), minutes: 60)
        XCTAssertTrue(timeline([yesterday, tomorrow]).blocks.isEmpty)
    }

    func testEventsCrossingMidnightAreClippedToTheDay() {
        let flight = TestSupport.event("Flight", start: at(18, 40), minutes: 16 * 60)
        let lateShow = TestSupport.event("Late show", start: at(23, day: 1), minutes: 120)
        let t = timeline([flight, lateShow])
        XCTAssertEqual(block(t, "Flight")?.startMinute, 18 * 60 + 40)
        XCTAssertEqual(block(t, "Flight")?.endMinute, 24 * 60)
        XCTAssertEqual(block(t, "Late show")?.startMinute, 0)
        XCTAssertEqual(block(t, "Late show")?.endMinute, 60)
    }

    func testOverlappingEventsSitSideBySide() throws {
        let review = TestSupport.event("Review", start: at(10, 15), minutes: 45)
        let coffee = TestSupport.event("Coffee", start: at(10, 30), minutes: 45)
        let focus = TestSupport.event("Focus", start: at(11, 30), minutes: 90)
        let t = timeline([coffee, focus, review])

        let r = try XCTUnwrap(block(t, "Review")), c = try XCTUnwrap(block(t, "Coffee")), f = try XCTUnwrap(block(t, "Focus"))
        XCTAssertEqual([r.column, r.columns], [0, 2])
        XCTAssertEqual([c.column, c.columns], [1, 2])
        XCTAssertEqual([f.column, f.columns], [0, 1], "Focus starts after both end, so it gets the full width")
    }

    func testFreedColumnsAreReused() throws {
        let long = TestSupport.event("Long", start: at(9), minutes: 180)
        let first = TestSupport.event("First", start: at(9, 30), minutes: 30)
        let second = TestSupport.event("Second", start: at(10, 30), minutes: 30)
        let t = timeline([long, first, second])
        XCTAssertEqual(try XCTUnwrap(block(t, "First")).column, 1)
        XCTAssertEqual(try XCTUnwrap(block(t, "Second")).column, 1)
        XCTAssertTrue(t.blocks.allSatisfy { $0.columns == 2 })
    }

    func testShortEventsGetARoomyBlockWithoutCrowdingTheNextOne() throws {
        let quick = TestSupport.event("Quick", start: at(9), minutes: 5)
        let next = TestSupport.event("Next", start: at(9, 10), minutes: 30)
        let t = timeline([quick, next])
        let q = try XCTUnwrap(block(t, "Quick"))
        XCTAssertEqual(q.endMinute - q.startMinute, DayTimeline.minimumMinutes)
        XCTAssertEqual(q.columns, 2, "The stretched block would cover Next, so they share the row")
    }

    @MainActor
    func testEventsViewIsSavedAndDefaultsToAgenda() {
        let defaults = UserDefaults(suiteName: "OrbitEventsView-\(UUID().uuidString)")!
        XCTAssertEqual(Preferences(defaults: defaults).eventsView, .agenda)
        Preferences(defaults: defaults).eventsView = .day
        XCTAssertEqual(Preferences(defaults: defaults).eventsView, .day)
    }
}
