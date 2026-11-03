import XCTest
@testable import Orbit

final class DayInsightsTests: XCTestCase {

    private let calendar = TestSupport.calendar()
    private let day = TestSupport.date(2026, 10, 31)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        TestSupport.date(2026, 10, 31, hour, minute)
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.string(45 * 60), "45m")
        XCTAssertEqual(DurationText.string(2 * 3600), "2h")
        XCTAssertEqual(DurationText.string(2.5 * 3600), "2h 30m")
    }

    func testSummaryMergesOverlappingEvents() {
        let events = [
            TestSupport.event("A", start: at(9), minutes: 60),
            TestSupport.event("B", start: at(9, 30), minutes: 60),
            TestSupport.event("C", start: at(14), minutes: 30),
            TestSupport.event("Holiday", start: day, minutes: 24 * 60, isAllDay: true),
        ]
        let summary = DaySummary(events: events, day: day, calendar: calendar)
        XCTAssertEqual(summary.eventCount, 4)
        XCTAssertEqual(summary.busy, 2 * 3600)
        XCTAssertEqual(summary.text, "4 events · 2h busy")
    }

    func testSummaryWithoutEvents() {
        XCTAssertEqual(DaySummary(events: [], day: day, calendar: calendar).text, "No events today")
    }

    func testFreeGapsBetweenEventsInWorkday() {
        let events = [
            TestSupport.event("Standup", start: at(9), minutes: 30),
            TestSupport.event("Lunch", start: at(12), minutes: 60),
            TestSupport.event("Short break", start: at(13, 10), minutes: 20),
        ]
        let gaps = BusyTime.freeGaps(in: events, on: day, now: at(7), calendar: calendar)
        XCTAssertEqual(gaps, [
            FreeGap(start: at(9, 30), end: at(12)),
            FreeGap(start: at(13, 30), end: at(18)),
        ])
    }

    func testFreeGapsStartFromNow() {
        let gaps = BusyTime.freeGaps(in: [], on: day, now: at(16, 15), calendar: calendar)
        XCTAssertEqual(gaps, [FreeGap(start: at(16, 15), end: at(18))])
    }

    func testNoFreeGapsAfterWorkday() {
        XCTAssertEqual(BusyTime.freeGaps(in: [], on: day, now: at(19), calendar: calendar), [])
    }

    func testDayProgress() {
        let progress = DayProgress(date: at(18), calendar: calendar)
        XCTAssertEqual(progress.fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(progress.remaining, 6 * 3600)
    }
}

final class DisplayOptionsTests: XCTestCase {

    func testTitleFilterKeywords() {
        XCTAssertEqual(TitleFilter.keywords(from: " daycare, school run ,, "), ["daycare", "school run"])
    }

    func testTitleFilterMatchesIgnoringCaseAndAccents() {
        let keywords = ["daycare", "creche"]
        XCTAssertTrue(TitleFilter.isIgnored("Daycare pickup", keywords: keywords))
        XCTAssertTrue(TitleFilter.isIgnored("Crèche drop-off", keywords: keywords))
        XCTAssertFalse(TitleFilter.isIgnored("Design review", keywords: keywords))
    }

    func testMapsLinks() {
        XCTAssertEqual(MapsProvider.apple.url(for: "1 Main St")?.absoluteString, "https://maps.apple.com/?q=1%20Main%20St")
        XCTAssertEqual(
            MapsProvider.google.url(for: "Café Roma")?.absoluteString,
            "https://www.google.com/maps/search/?api=1&query=Caf%C3%A9%20Roma"
        )
        XCTAssertNil(MapsProvider.apple.url(for: "  "))
    }

    func testCustomServiceHostFromLinkOrDomain() {
        XCTAssertEqual(CustomVideoService.normalizedHost(from: "https://www.Whereby.com/team-room"), "whereby.com")
        XCTAssertEqual(CustomVideoService.normalizedHost(from: "meet.example.com"), "meet.example.com")
        XCTAssertNil(CustomVideoService.normalizedHost(from: "not a domain"))
    }

    func testCustomHostsEnableMeetingLinks() {
        let fields = ["Join at https://call.example.com/r/42"]
        XCTAssertNil(MeetingLinkDetector.firstMeetingURL(in: fields))
        XCTAssertEqual(MeetingLinkDetector.firstMeetingURL(in: fields, extraHosts: ["call.example.com"])?.host, "call.example.com")
    }
}
