import XCTest
@testable import Orbit

final class AttendanceTests: XCTestCase {

    private func event(you response: Guest.Response?, organizer: Bool = false) -> CalendarEvent {
        var event = TestSupport.event("Review", start: TestSupport.date(2026, 10, 31, 13), minutes: 45)
        if let response {
            event.guests = [
                Guest(name: "Priya", response: .accepted, isOrganizer: !organizer),
                Guest(name: "You", response: response, isOrganizer: organizer, isYou: true),
            ]
        }
        return event
    }

    func testYourOwnEventsCountAsAttending() {
        XCTAssertEqual(event(you: nil).attendance, .attending)
        XCTAssertEqual(event(you: .pending, organizer: true).attendance, .attending, "You organised it, so there's nothing to answer")
    }

    func testYourReplyDecidesAttendance() {
        XCTAssertEqual(event(you: .accepted).attendance, .attending)
        XCTAssertEqual(event(you: .pending).attendance, .notAnswered)
        XCTAssertEqual(event(you: .tentative).attendance, .maybe)
        XCTAssertEqual(event(you: .declined).attendance, .declined)
    }

    func testInvitesWhereYouArentListedCountAsAttending() {
        var event = TestSupport.event("Team sync", start: TestSupport.date(2026, 10, 31, 9), minutes: 30)
        event.guests = [Guest(name: "Priya", response: .accepted, isOrganizer: true)]
        XCTAssertEqual(event.attendance, .attending)
    }

    func testOnlyAttendingHasNoLabel() {
        XCTAssertNil(Attendance.attending.label)
        XCTAssertEqual(Attendance.notAnswered.label, "Not answered")
        XCTAssertEqual(Attendance.maybe.label, "Maybe")
        XCTAssertEqual(Attendance.declined.label, "Declined")
    }
}

@MainActor
final class DeclinedEventsTests: XCTestCase {

    private let now = StateFixture.now

    private func invite(_ title: String, minutesFromNow: Double, you response: Guest.Response) -> CalendarEvent {
        var event = TestSupport.event(title, start: now.addingTimeInterval(minutesFromNow * 60), minutes: 30)
        event.guests = [Guest(name: "You", response: response, isYou: true), Guest(name: "Sam", response: .accepted, isOrganizer: true)]
        return event
    }

    func testDeclinedEventsAreHiddenUnlessTurnedOn() async {
        let state = await StateFixture.make { store, preferences in
            preferences.menuBarFormat.preset = .agenda
            store.add(self.invite("Declined call", minutesFromNow: 5, you: .declined))
            store.add(self.invite("Maybe call", minutesFromNow: 20, you: .tentative))
        }.state
        XCTAssertFalse(state.preferences.showDeclinedEvents, "Off by default")
        XCTAssertEqual(state.agendaDays.first?.events.map(\.title), ["Maybe call"])

        state.preferences.showDeclinedEvents = true
        state.reload()
        XCTAssertEqual(state.agendaDays.first?.events.map(\.title), ["Declined call", "Maybe call"])
    }

    func testMenuBarAndJoinSkipDeclinedEventsEvenWhenShown() async {
        let state = await StateFixture.make { store, preferences in
            preferences.menuBarFormat.preset = .agenda
            preferences.showDeclinedEvents = true
            store.add(self.invite("Declined call", minutesFromNow: 5, you: .declined), link: "https://zoom.us/j/1")
            store.add(self.invite("Real call", minutesFromNow: 20, you: .accepted), link: "https://zoom.us/j/2")
        }.state
        XCTAssertEqual(state.menuBarTitle, "Real call in 20m")
        XCTAssertEqual(state.nextMeetingURL?.absoluteString, "https://zoom.us/j/2")
    }

    func testEventsDensityAlsoSetsTheDayViewsHourHeight() {
        let heights = Density.allCases.map(\.hourHeight)
        XCTAssertEqual(Density.compact.hourHeight, 40, "Compact keeps the Day view as it was")
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, heights.count)
    }
}
