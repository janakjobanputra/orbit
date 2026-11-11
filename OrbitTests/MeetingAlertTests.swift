import XCTest
@testable import Orbit

final class MeetingAppLinkTests: XCTestCase {

    private func app(_ link: String) -> String? {
        MeetingAppLink.appURL(for: URL(string: link)!)?.absoluteString
    }

    func testZoomMeetingsOpenInZoom() {
        XCTAssertEqual(app("https://us02web.zoom.us/j/81234567890?pwd=AbC.123"),
                       "zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=AbC.123")
        XCTAssertEqual(app("https://zoom.us/j/123456789"), "zoommtg://zoom.us/join?action=join&confno=123456789")
        XCTAssertEqual(app("https://acme.zoom.us/w/99887766?tk=x"), "zoommtg://acme.zoom.us/join?action=join&confno=99887766")
    }

    func testOtherZoomLinksStayOnTheWeb() {
        XCTAssertNil(app("https://acme.zoom.us/my/janak"), "Personal links have no meeting number")
        XCTAssertNil(app("https://zoom.us/j/not-a-number"))
        XCTAssertNil(app("https://notzoom.us/j/123"))
    }

    func testTeamsMeetingsOpenInTeams() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d"
        XCTAssertEqual(app(link), "msteams:/l/meetup-join/19%3ameeting_ABC%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d")
        XCTAssertNil(app("https://teams.microsoft.com/v2/"))
    }

    func testMeetAndWebexStayOnTheWeb() {
        XCTAssertNil(app("https://meet.google.com/abc-defg-hij"))
        XCTAssertNil(app("https://acme.webex.com/acme/j.php?MTID=m123"))
    }
}

@MainActor
final class MeetingAlertTests: XCTestCase {

    // StateFixture's clock starts at Saturday 31 October 2026, 9:47.
    private func call(_ title: String, at hour: Int, _ minute: Int, link: String? = "https://zoom.us/j/123456789") -> CalendarEvent {
        var event = TestSupport.event(title, start: TestSupport.date(2026, 10, 31, hour, minute), minutes: 30)
        event.meetingURL = link.flatMap(URL.init(string:))
        return event
    }

    private func make(_ events: [CalendarEvent], configure: @MainActor (Preferences) -> Void = { _ in }) async -> (AppState, TestClock) {
        let (state, _, clock) = await StateFixture.make { store, preferences in
            events.forEach { store.add($0, link: $0.meetingURL?.absoluteString) }
            configure(preferences)
        }
        return (state, clock)
    }

    private func move(_ clock: TestClock, _ state: AppState, to hour: Int, _ minute: Int) {
        clock.now = TestSupport.date(2026, 10, 31, hour, minute)
        state.tick()
    }

    func testAlertsAMinuteBeforeByDefault() async {
        let (state, clock) = await make([call("Design review", at: 10, 0)])
        XCTAssertEqual(state.meetingAlerts, [])
        move(clock, state, to: 9, 58)
        XCTAssertEqual(state.meetingAlerts, [])
        move(clock, state, to: 9, 59)
        XCTAssertEqual(state.meetingAlerts.map(\.title), ["Design review"])
    }

    func testDismissedAlertsStayDismissed() async {
        let (state, clock) = await make([call("Design review", at: 10, 0)])
        move(clock, state, to: 9, 59)
        state.dismissAlert(state.meetingAlerts[0])
        move(clock, state, to: 10, 0)
        move(clock, state, to: 10, 1)
        XCTAssertEqual(state.meetingAlerts, [])
    }

    func testJoiningOpensTheCallAndClosesTheAlert() async {
        let (state, clock) = await make([call("Design review", at: 10, 0)])
        var opened: [URL] = []
        state.openMeeting = { opened.append($0) }
        move(clock, state, to: 9, 59)
        state.join(fromAlert: state.meetingAlerts[0])
        XCTAssertEqual(opened.map(\.absoluteString), ["https://zoom.us/j/123456789"])
        XCTAssertEqual(state.meetingAlerts, [])
    }

    func testAMacThatWakesLateStillGetsTheAlertButNotLongAfter() async {
        let (state, clock) = await make([call("Standup", at: 10, 0), call("Earlier", at: 9, 30)])
        move(clock, state, to: 10, 4)
        XCTAssertEqual(state.meetingAlerts.map(\.title), ["Standup"], "Four minutes in still counts; half an hour doesn't")
    }

    func testAlertsCloseWhenTheMeetingEnds() async {
        let (state, clock) = await make([call("Standup", at: 10, 0)])
        move(clock, state, to: 10, 2)
        XCTAssertEqual(state.meetingAlerts.count, 1)
        move(clock, state, to: 10, 30)
        XCTAssertEqual(state.meetingAlerts, [])
    }

    func testOnlyVideoMeetingsUnlessYouAskForAll() async {
        let lunch = call("Lunch", at: 10, 0, link: nil)
        let (state, clock) = await make([lunch])
        move(clock, state, to: 9, 59)
        XCTAssertEqual(state.meetingAlerts, [])

        let (all, allClock) = await make([lunch]) { $0.meetingAlertScope = .allEvents }
        move(allClock, all, to: 9, 59)
        XCTAssertEqual(all.meetingAlerts.map(\.title), ["Lunch"])
    }

    func testLeadTimeAndTurningAlertsOff() async {
        let (state, clock) = await make([call("Planning", at: 10, 0)]) { $0.meetingAlertLeadMinutes = 10 }
        move(clock, state, to: 9, 50)
        XCTAssertEqual(state.meetingAlerts.count, 1)

        let (off, offClock) = await make([call("Planning", at: 10, 0)]) { $0.meetingAlerts = false }
        move(offClock, off, to: 9, 59)
        XCTAssertEqual(off.meetingAlerts, [])
    }

    func testHiddenCalendarsAndAllDayEventsDontAlert() async {
        var holiday = TestSupport.event("Holiday", start: TestSupport.date(2026, 10, 31), minutes: 24 * 60, isAllDay: true)
        holiday.meetingURL = URL(string: "https://zoom.us/j/1")
        var hidden = call("Hidden", at: 10, 0)
        hidden = CalendarEvent(id: hidden.id, title: hidden.title, start: hidden.start, end: hidden.end, isAllDay: false,
                               calendarID: "home", color: .fallback, location: nil, meetingURL: hidden.meetingURL)
        let (state, clock) = await make([holiday, hidden]) { $0.setCalendar("home", visible: false) }
        move(clock, state, to: 9, 59)
        XCTAssertEqual(state.meetingAlerts, [])
    }

    func testTwoMeetingsAtOnceBothShow() async {
        let (state, clock) = await make([call("B call", at: 10, 0), call("A call", at: 10, 0)])
        move(clock, state, to: 9, 59)
        XCTAssertEqual(state.meetingAlerts.map(\.title), ["A call", "B call"])
    }

    func testTheSampleAlertOpensNothing() async {
        let (state, _) = await make([])
        var opened: [URL] = []
        state.openMeeting = { opened.append($0) }
        state.showSampleMeetingAlert()
        state.showSampleMeetingAlert()
        XCTAssertEqual(state.meetingAlerts.count, 1, "Showing it again replaces it")
        state.join(fromAlert: state.meetingAlerts[0])
        XCTAssertEqual(opened, [])
        XCTAssertEqual(state.meetingAlerts, [])
    }

    func testTiming() {
        let event = call("X", at: 10, 0)
        XCTAssertEqual(MeetingAlertSchedule.timing(of: event, now: TestSupport.date(2026, 10, 31, 9, 58)), "Starts in 2 min")
        XCTAssertEqual(MeetingAlertSchedule.timing(of: event, now: TestSupport.date(2026, 10, 31, 10, 0, 20)), "Starting now")
        XCTAssertEqual(MeetingAlertSchedule.timing(of: event, now: TestSupport.date(2026, 10, 31, 10, 3)), "Started 3 min ago")
    }
}
