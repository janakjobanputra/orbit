import Foundation

struct CalendarDay: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let date: Date
        let isInDisplayedMonth: Bool
    }

    let date: Date
    let isInDisplayedMonth: Bool

    /// The 30th of November is a different cell in November's grid than in December's, so SwiftUI
    /// doesn't carry its styling over when the month changes.
    var id: ID { ID(date: date, isInDisplayedMonth: isInDisplayedMonth) }
}

/// Builds the grid shown for a month: whole weeks, with between one day and one full week of the previous
/// month before it and of the next month after it. That works out to five or six rows.
enum MonthGrid {

    static func days(for month: Date, calendar: Calendar) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // A month that starts on the first weekday gets the whole previous week; likewise at the end.
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let leadingDays = offset == 0 ? 7 : offset
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth),
              let monthLength = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }
        let partialTrailing = (7 - (leadingDays + monthLength) % 7) % 7
        let dayCount = leadingDays + monthLength + (partialTrailing == 0 ? 7 : partialTrailing)

        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let inMonth = calendar.isDate(date, equalTo: firstOfMonth, toGranularity: .month)
            return CalendarDay(date: date, isInDisplayedMonth: inMonth)
        }
    }

    /// Weekday symbols ordered to start on the calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
