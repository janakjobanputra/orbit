import Foundation
@testable import Orbit

enum TestSupport {

    static let utc = TimeZone(identifier: "UTC")!

    static func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func event(
        _ title: String,
        start: Date,
        minutes: Int,
        isAllDay: Bool = false,
        calendarID: String = "work"
    ) -> CalendarEvent {
        CalendarEvent(
            id: "\(title)-\(start.timeIntervalSince1970)",
            title: title,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: isAllDay,
            calendarID: calendarID,
            color: .fallback,
            location: nil,
            meetingURL: nil
        )
    }
}
