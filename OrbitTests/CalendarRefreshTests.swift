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

        state.showPage(offset: 1)
        state.showPage(offset: 1)
        state.showPage(offset: -1)

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
        state.showPage(offset: 1)
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

/// The rolling 3-week calendar: this week in the middle, a week at a time.
@MainActor
final class ThreeWeekViewTests: XCTestCase {

    // Saturday 31 October 2026, weeks starting on Sunday: 18 October to 7 November.
    private let today = TestSupport.date(2026, 10, 31, 9)

    private func make(_ setUp: @MainActor (FakeEventStore, Preferences) -> Void = { _, _ in }) async -> (AppState, FakeEventStore) {
        let (state, store, _) = await StateFixture.make(at: today) { store, preferences in
            preferences.weekStart = .sunday
            preferences.calendarSpan = .threeWeeks
            setUp(store, preferences)
        }
        return (state, store)
    }

    func testShowsTheWeeksEitherSideOfThisOne() async {
        let (state, _) = await make()
        XCTAssertEqual(state.gridDays.map(\.date).first, TestSupport.date(2026, 10, 18))
        XCTAssertEqual(state.gridDays.map(\.date).last, TestSupport.date(2026, 11, 7))
    }

    func testArrowsMoveAWeekAndTodayComesBack() async {
        let (state, _) = await make()
        state.showPage(offset: 1)
        XCTAssertEqual(state.gridDays.first?.date, TestSupport.date(2026, 10, 25))
        state.showPage(offset: -2)
        XCTAssertEqual(state.gridDays.first?.date, TestSupport.date(2026, 10, 11))
        state.showToday()
        XCTAssertEqual(state.gridDays.first?.date, TestSupport.date(2026, 10, 18))
    }

    func testDotsFollowTheWeeksIntoTheNextMonth() async {
        let dinner = TestSupport.event("Dinner", start: TestSupport.date(2026, 11, 26, 19), minutes: 90)
        let (state, _) = await make { store, _ in store.add(dinner) }
        XCTAssertEqual(state.events(on: dinner.start), [], "Not in the first three weeks")
        state.showPage(offset: 3)
        XCTAssertEqual(state.events(on: dinner.start).map(\.title), ["Dinner"])
    }

    func testSwitchingBetweenMonthAndThreeWeeksNeedsNoFetch() async {
        let (state, store) = await make()
        let fetches = store.summaryFetches
        state.preferences.calendarSpan = .month
        state.preferences.calendarSpan = .threeWeeks
        XCTAssertEqual(store.summaryFetches, fetches)
    }

    func testPagingWithinTheSameWeekDoesntFetch() async {
        let (state, store) = await make()
        let fetches = store.summaryFetches
        // Today is Saturday 31 October; Tuesday 3 November starts the next week.
        state.displayedMonth = TestSupport.date(2026, 11, 3)
        XCTAssertEqual(store.summaryFetches, fetches + 1, "Moved a week")
        state.displayedMonth = TestSupport.date(2026, 11, 5)
        XCTAssertEqual(store.summaryFetches, fetches + 1, "Same week")
    }

    func testGoingToADayPutsItsWeekInTheMiddle() async {
        let (state, _) = await make()
        state.show(date: TestSupport.date(2027, 2, 10))
        XCTAssertEqual(state.gridDays[7].date, TestSupport.date(2027, 2, 7))
        XCTAssertTrue(state.calendar.isDate(state.selectedDate, inSameDayAs: TestSupport.date(2027, 2, 10)))
    }
}
