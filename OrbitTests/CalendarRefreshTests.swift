import XCTest
@testable import Orbit

/// Things that change outside Orbit while it runs, which used to need a restart to show up.
@MainActor
final class CalendarRefreshTests: XCTestCase {

    private let lunch = TestSupport.event("Lunch with Sam", start: TestSupport.date(2026, 10, 31, 12), minutes: 60, calendarID: "google")

    func testAnAccountAddedWhileRunningAppearsWhenTheCalendarOpens() async {
        let (state, store, _) = await StateFixture.make { store, _ in
            store.calendarList = [StateFixture.calendarInfo("work")]
        }
        store.unseenUntilRefresh = ([StateFixture.calendarInfo("google", source: "Google")], [lunch])

        state.reload()
        XCTAssertFalse(state.calendars.map(\.id).contains("google"), "A plain reload still has the old account list")

        state.refreshCalendars()
        XCTAssertEqual(state.calendars.map(\.id), ["work", "google"])
        XCTAssertEqual(state.events(on: lunch.start).map(\.title), ["Lunch with Sam"])
        XCTAssertTrue(state.agendaDays.flatMap(\.events).contains { $0.title == "Lunch with Sam" })
    }

    func testAccessTurnedOnInSystemSettingsIsPickedUpWithoutARestart() async {
        let (state, store, _) = await StateFixture.make { store, _ in
            store.access = .denied
            store.add(TestSupport.event("Standup", start: TestSupport.date(2026, 10, 31, 10), minutes: 15))
        }
        XCTAssertEqual(state.access, .denied)
        XCTAssertTrue(state.agendaDays.flatMap(\.events).isEmpty)

        store.access = .granted
        state.refreshCalendars()
        XCTAssertEqual(state.access, .granted)
        XCTAssertEqual(state.agendaDays.flatMap(\.events).map(\.title), ["Standup"])
    }

    func testTheMinuteTickNoticesAccessChanging() async {
        let (state, store, clock) = await StateFixture.make { store, _ in store.access = .denied }
        store.access = .granted
        clock.now = clock.now.addingTimeInterval(60)
        state.tick()
        XCTAssertEqual(state.access, .granted)
    }

    func testTheQuarterHourTickLooksForNewAccounts() async {
        let (state, store, clock) = await StateFixture.make(at: TestSupport.date(2026, 10, 31, 9, 59))
        store.unseenUntilRefresh = ([StateFixture.calendarInfo("google", source: "Google")], [])
        clock.now = TestSupport.date(2026, 10, 31, 10, 0)
        state.tick()
        XCTAssertTrue(state.calendars.map(\.id).contains("google"))
    }
}

/// Paging through months should only redo the month grid.
@MainActor
final class MonthPagingTests: XCTestCase {

    func testChangingMonthOnlyFetchesTheGrid() async {
        let (state, store, _) = await StateFixture.make()
        let full = store.fullFetches
        let summaries = store.summaryFetches

        state.showMonth(offset: 1)
        state.showMonth(offset: 1)
        state.showMonth(offset: -1)

        XCTAssertEqual(store.fullFetches, full, "The agenda and menu bar don't change with the month")
        XCTAssertEqual(store.summaryFetches, summaries + 3)
    }

    func testGridDotsCoverEveryDayOfAMultiDayEvent() async {
        let trip = TestSupport.event("Lisbon", start: TestSupport.date(2026, 11, 2), minutes: 3 * 24 * 60, isAllDay: true)
        let lateCall = TestSupport.event("Late call", start: TestSupport.date(2026, 11, 9, 23, 30), minutes: 60)
        let (state, _, _) = await StateFixture.make { store, _ in
            store.add(trip)
            store.add(lateCall)
        }
        state.showMonth(offset: 1)
        let titles = { (day: Int) in state.events(on: TestSupport.date(2026, 11, day, 15)).map(\.title) }
        XCTAssertEqual(titles(1), [])
        XCTAssertEqual(titles(2), ["Lisbon"])
        XCTAssertEqual(titles(4), ["Lisbon"])
        XCTAssertEqual(titles(5), [], "An all-day event ending at midnight doesn't spill into the next day")
        XCTAssertEqual(titles(9), ["Late call"])
        XCTAssertEqual(titles(10), ["Late call"], "Runs past midnight")
    }

    func testGridDotsStillFollowHiddenCalendars() async {
        let (state, _, _) = await StateFixture.make { store, preferences in
            store.add(TestSupport.event("Gym", start: TestSupport.date(2026, 10, 31, 18), minutes: 60, calendarID: "personal"))
            preferences.setCalendar("personal", visible: false)
        }
        XCTAssertEqual(state.events(on: TestSupport.date(2026, 10, 31)), [])
        state.preferences.setCalendar("personal", visible: true)
        XCTAssertEqual(state.events(on: TestSupport.date(2026, 10, 31)).map(\.title), ["Gym"])
    }
}
