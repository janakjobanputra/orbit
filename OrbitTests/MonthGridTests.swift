import XCTest
@testable import Orbit

final class MonthGridTests: XCTestCase {

    func testMonthStartingOnFirstWeekdayShowsThePreviousWeek() {
        let sundayStart = TestSupport.calendar(firstWeekday: 1)
        // November 2026 starts on a Sunday: the whole week of 25–31 October comes first.
        let november = MonthGrid.days(for: TestSupport.date(2026, 11, 10), calendar: sundayStart)
        XCTAssertEqual(november.first?.date, TestSupport.date(2026, 10, 25))
        XCTAssertEqual(november.last?.date, TestSupport.date(2026, 12, 5))
        XCTAssertEqual(november.count, 42)
        // February 2026 starts on a Sunday and ends on a Saturday: a full week either side.
        let february = MonthGrid.days(for: TestSupport.date(2026, 2, 10), calendar: sundayStart)
        XCTAssertEqual(february.first?.date, TestSupport.date(2026, 1, 25))
        XCTAssertEqual(february.last?.date, TestSupport.date(2026, 3, 7))
        // October 2026 ends on a Saturday: the whole week of 1–7 November follows.
        let october = MonthGrid.days(for: TestSupport.date(2026, 10, 15), calendar: sundayStart)
        XCTAssertEqual(october.last?.date, TestSupport.date(2026, 11, 7))
        // September 2026 runs Tuesday to Wednesday: partial weeks either side, five rows.
        XCTAssertEqual(MonthGrid.days(for: TestSupport.date(2026, 9, 15), calendar: sundayStart).count, 35)
    }

    func testOneDayToOneWeekOfEachNeighbouringMonth() {
        for firstWeekday in [1, 2] {
            let calendar = TestSupport.calendar(firstWeekday: firstWeekday)
            for year in [2026, 2027, 2028] {
                for month in 1...12 {
                    let days = MonthGrid.days(for: TestSupport.date(year, month, 15), calendar: calendar)
                    let leading = days.prefix { !$0.isInDisplayedMonth }.count
                    let trailing = days.reversed().prefix { !$0.isInDisplayedMonth }.count
                    let label = "\(year)-\(month), week starts \(firstWeekday)"
                    XCTAssertTrue((1...7).contains(leading), label)
                    XCTAssertTrue((1...7).contains(trailing), label)
                    XCTAssertTrue([35, 42].contains(days.count), label)
                    XCTAssertEqual(calendar.component(.weekday, from: days[0].date), firstWeekday, label)
                }
            }
        }
    }

    func testSundayStartGridBeginsOnPrecedingSunday() {
        // 1 October 2026 is a Thursday.
        let days = MonthGrid.days(for: TestSupport.date(2026, 10, 15), calendar: TestSupport.calendar(firstWeekday: 1))
        XCTAssertEqual(days.first?.date, TestSupport.date(2026, 9, 27))
        XCTAssertEqual(days.first?.isInDisplayedMonth, false)
    }

    func testMondayStartGridBeginsOnPrecedingMonday() {
        let days = MonthGrid.days(for: TestSupport.date(2026, 10, 15), calendar: TestSupport.calendar(firstWeekday: 2))
        XCTAssertEqual(days.first?.date, TestSupport.date(2026, 9, 28))
    }

    func testMarksDaysInDisplayedMonth() {
        let days = MonthGrid.days(for: TestSupport.date(2026, 10, 15), calendar: TestSupport.calendar())
        XCTAssertEqual(days.filter(\.isInDisplayedMonth).count, 31)
    }

    func testWeekdaySymbolsFollowFirstWeekday() {
        var calendar = TestSupport.calendar(firstWeekday: 2)
        calendar.locale = Locale(identifier: "en_US")
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: calendar), ["M", "T", "W", "T", "F", "S", "S"])
    }
}
