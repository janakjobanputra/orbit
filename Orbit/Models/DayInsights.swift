import Foundation

enum DurationText {

    /// "45m", "2h", "2h 30m".
    static func string(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }
}

/// "3 events · 2h 30m busy" for one day.
struct DaySummary: Equatable, Sendable {

    let eventCount: Int
    let busy: TimeInterval

    init(events: [CalendarEvent], day: Date, calendar: Calendar) {
        let dayEvents = events.filter { $0.overlaps(day: day, calendar: calendar) }
        eventCount = dayEvents.count
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        busy = BusyTime.merged(dayEvents, from: dayStart, to: dayEnd).reduce(0) { $0 + $1.duration }
    }

    var text: String {
        switch eventCount {
        case 0: return "No events today"
        case 1 where busy == 0: return "1 event"
        case _ where busy == 0: return "\(eventCount) events"
        case 1: return "1 event · \(DurationText.string(busy)) busy"
        default: return "\(eventCount) events · \(DurationText.string(busy)) busy"
        }
    }
}

struct FreeGap: Hashable, Identifiable, Sendable {
    let start: Date
    let end: Date

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum BusyTime {

    /// Timed events clipped to the window, with overlaps merged.
    static func merged(_ events: [CalendarEvent], from start: Date, to end: Date) -> [DateInterval] {
        let inWindow = events.filter { !$0.isAllDay && $0.end > start && $0.start < end }
        let clipped: [DateInterval] = inWindow.map { event in
            DateInterval(start: max(event.start, start), end: min(event.end, end))
        }
        let intervals = clipped.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Free stretches of at least `minimum` inside the working day, ignoring time already past.
    static func freeGaps(
        in events: [CalendarEvent],
        on day: Date,
        now: Date,
        calendar: Calendar,
        workday: (start: Int, end: Int) = (9, 18),
        minimum: TimeInterval = 30 * 60
    ) -> [FreeGap] {
        guard var windowStart = calendar.date(bySettingHour: workday.start, minute: 0, second: 0, of: day),
              let windowEnd = calendar.date(bySettingHour: workday.end, minute: 0, second: 0, of: day) else { return [] }
        windowStart = max(windowStart, now)
        guard windowStart < windowEnd else { return [] }

        var gaps: [FreeGap] = []
        var cursor = windowStart
        for busy in merged(events, from: windowStart, to: windowEnd) {
            if busy.start.timeIntervalSince(cursor) >= minimum {
                gaps.append(FreeGap(start: cursor, end: busy.start))
            }
            cursor = max(cursor, busy.end)
        }
        if windowEnd.timeIntervalSince(cursor) >= minimum {
            gaps.append(FreeGap(start: cursor, end: windowEnd))
        }
        return gaps
    }
}

struct DayProgress: Equatable, Sendable {

    /// Share of today already elapsed, from 0 to 1.
    let fraction: Double
    let remaining: TimeInterval

    init(date: Date, calendar: Calendar) {
        guard let day = calendar.dateInterval(of: .day, for: date) else {
            fraction = 0
            remaining = 0
            return
        }
        fraction = min(max(date.timeIntervalSince(day.start) / day.duration, 0), 1)
        remaining = max(day.end.timeIntervalSince(date), 0)
    }
}
