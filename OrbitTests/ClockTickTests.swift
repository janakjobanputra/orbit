import XCTest
@testable import Orbit

@MainActor
final class ClockTickTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        TestSupport.date(2026, 10, 31, hour, minute, second)
    }

    func testSecondsAreDetectedInTheShownPatterns() {
        var format = MenuBarFormat()
        format.preset = .custom
        format.customTokens = [.time]

        format.timePattern = "h:mm:ss"
        XCTAssertTrue(format.showsSeconds)
        format.timePattern = "h:mm"
        XCTAssertFalse(format.showsSeconds)
        format.timePattern = "h:mm 'sharp'"
        XCTAssertFalse(format.showsSeconds, "Letters inside quotes are literal text")

        format.timePattern = "h:mm:ss"
        format.customTokens = [.date]
        XCTAssertFalse(format.showsSeconds, "The time isn't shown, so its seconds don't matter")
        format.datePattern = "EEE ss"
        XCTAssertTrue(format.showsSeconds)
    }

    func testMenuBarTicksEverySecondWhenItShowsSeconds() async {
        let (state, _, clock) = await StateFixture.make(at: at(9, 47)) { _, preferences in
            preferences.menuBarFormat.preset = .custom
            preferences.menuBarFormat.customTokens = [.time]
            preferences.menuBarFormat.timePattern = "h:mm:ss"
        }
        XCTAssertEqual(state.menuBarTitle, "9:47:00")

        clock.now = at(9, 47, 5)
        state.tick()
        XCTAssertEqual(state.menuBarTitle, "9:47:05")
        XCTAssertEqual(state.now, at(9, 47), "The calendar itself only moves on each minute")

        clock.now = at(9, 48, 1)
        state.tick()
        XCTAssertEqual(state.menuBarTitle, "9:48:01")
        XCTAssertEqual(state.now, at(9, 48, 1))
    }

    func testMenuBarWithoutSecondsOnlyChangesEachMinute() async {
        let (state, _, clock) = await StateFixture.make(at: at(9, 47)) { _, preferences in
            preferences.menuBarFormat.preset = .custom
            preferences.menuBarFormat.customTokens = [.time]
            preferences.menuBarFormat.timePattern = "h:mm"
        }
        clock.now = at(9, 47, 30)
        state.tick()
        XCTAssertEqual(state.now, at(9, 47))
        XCTAssertEqual(state.menuBarTitle, "9:47")

        clock.now = at(9, 48)
        state.tick()
        XCTAssertEqual(state.menuBarTitle, "9:48")
    }

    func testTickWaitsUntilTheNextSecondOrMinute() {
        let date = at(9, 47, 12).addingTimeInterval(0.25)
        XCTAssertEqual(AppState.nextTick(after: date, showsSeconds: true), at(9, 47, 13))
        XCTAssertEqual(AppState.nextTick(after: date, showsSeconds: false, calendar: TestSupport.calendar()), at(9, 48))
        XCTAssertEqual(AppState.nextTick(after: at(9, 47, 12), showsSeconds: true), at(9, 47, 13))
    }
}
