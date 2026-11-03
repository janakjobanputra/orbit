import XCTest
@testable import Orbit

final class CalendarEventTests: XCTestCase {

    private let calendar = TestSupport.calendar()
    private let day = TestSupport.date(2026, 10, 30)

    func testTimedEventOverlapsItsDay() {
        let event = TestSupport.event("Lunch", start: TestSupport.date(2026, 10, 30, 12), minutes: 60)
        XCTAssertTrue(event.overlaps(day: day, calendar: calendar))
        XCTAssertFalse(event.overlaps(day: TestSupport.date(2026, 10, 31), calendar: calendar))
    }

    func testAllDayEventDoesNotSpillIntoNextDay() {
        let event = TestSupport.event("Holiday", start: day, minutes: 24 * 60, isAllDay: true)
        XCTAssertTrue(event.overlaps(day: day, calendar: calendar))
        XCTAssertFalse(event.overlaps(day: TestSupport.date(2026, 10, 31), calendar: calendar))
    }

    func testOvernightEventOverlapsBothDays() {
        let event = TestSupport.event("Flight", start: TestSupport.date(2026, 10, 30, 22), minutes: 180)
        XCTAssertTrue(event.overlaps(day: day, calendar: calendar))
        XCTAssertTrue(event.overlaps(day: TestSupport.date(2026, 10, 31), calendar: calendar))
    }

    func testZeroLengthEventOverlapsItsDay() {
        let event = TestSupport.event("Reminder", start: TestSupport.date(2026, 10, 30, 9), minutes: 0)
        XCTAssertTrue(event.overlaps(day: day, calendar: calendar))
    }
}

final class MeetingLinkDetectorTests: XCTestCase {

    func testFindsZoomLinkInNotes() {
        let url = MeetingLinkDetector.firstMeetingURL(in: [nil, "Room 4", "Join: https://acme.zoom.us/j/123456?pwd=abc"])
        XCTAssertEqual(url?.host, "acme.zoom.us")
    }

    func testFindsGoogleMeetLinkInLocation() {
        let url = MeetingLinkDetector.firstMeetingURL(in: [nil, "https://meet.google.com/abc-defg-hij", nil])
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testPrefersEarlierFields() {
        let url = MeetingLinkDetector.firstMeetingURL(in: [
            "https://teams.microsoft.com/l/meetup-join/xyz",
            nil,
            "https://zoom.us/j/1",
        ])
        XCTAssertEqual(url?.host, "teams.microsoft.com")
    }

    func testIgnoresNonMeetingLinks() {
        XCTAssertNil(MeetingLinkDetector.firstMeetingURL(in: ["https://example.com/agenda", "https://notzoom.us/j/1"]))
    }
}
