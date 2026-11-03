import Foundation

struct AgendaDay: Identifiable, Hashable, Sendable {

    enum Kind: Hashable, Sendable {
        case today, tomorrow, other
    }

    let date: Date
    let kind: Kind
    let events: [CalendarEvent]

    var id: Date { date }

    /// Today, with nothing timed still in progress or to come.
    func hasNothingLeft(now: Date) -> Bool {
        kind == .today && !events.contains { !$0.isAllDay && $0.end > now }
    }
}

enum AgendaRow: Hashable, Identifiable, Sendable {
    case event(CalendarEvent)
    case free(FreeGap)
    case now

    var id: String {
        switch self {
        case .event(let event): "event-\(event.id)"
        case .free(let gap): "free-\(gap.start.timeIntervalSince1970)"
        case .now: "now"
        }
    }

    fileprivate var start: Date {
        switch self {
        case .event(let event): event.start
        case .free(let gap): gap.start
        case .now: .distantPast
        }
    }

    /// All-day events sit in the pinned header above the rest of the day.
    var isAllDay: Bool {
        if case .event(let event) = self { return event.isAllDay }
        return false
    }

    fileprivate var isFree: Bool {
        if case .free = self { return true }
        return false
    }
}

/// Groups events into the day-by-day list shown under the month grid.
enum Agenda {

    /// Days from `start` onwards. The first day always appears; later empty days only when `includeEmptyDays` is set.
    static func days(
        from start: Date,
        count: Int,
        events: [CalendarEvent],
        now: Date,
        calendar: Calendar,
        includeEmptyDays: Bool = false
    ) -> [AgendaDay] {
        let first = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 1)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let dayEvents = sorted(events.filter { $0.overlaps(day: date, calendar: calendar) })
            guard offset == 0 || includeEmptyDays || !dayEvents.isEmpty else { return nil }
            return AgendaDay(date: date, kind: kind(of: date, today: today, calendar: calendar), events: dayEvents)
        }
    }

    /// All-day events first, then by start time.
    static func sorted(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return (lhs.start, lhs.end, lhs.title) < (rhs.start, rhs.end, rhs.title)
        }
    }

    /// One day's list: all-day events, then events and free gaps in time order, with an optional "now" line
    /// placed above the first timed row that hasn't ended yet, so a meeting in progress sits below it.
    static func rows(events: [CalendarEvent], gaps: [FreeGap], now: Date?) -> [AgendaRow] {
        let sortedEvents = sorted(events)
        let allDay = sortedEvents.filter(\.isAllDay).map(AgendaRow.event)
        let timed: [AgendaRow] = (sortedEvents.filter { !$0.isAllDay }.map(AgendaRow.event) + gaps.map(AgendaRow.free))
            .sorted { lhs, rhs in
                // A gap that starts when an event does was left by an earlier event, so it goes first.
                lhs.start == rhs.start ? lhs.isFree && !rhs.isFree : lhs.start < rhs.start
            }
        var rows = allDay + timed
        if let now, !rows.isEmpty {
            let index = rows.firstIndex { row in
                switch row {
                case .event(let event): !event.isAllDay && event.end > now
                case .free(let gap): gap.end > now
                case .now: false
                }
            } ?? rows.count
            rows.insert(.now, at: index)
        }
        return rows
    }

    /// How long a finished event stays in today's list.
    static let recentlyFinishedWindow: TimeInterval = 60 * 60

    /// Today's list without events that are over, apart from the one that finished most recently, and only
    /// if that was within the last hour. All-day events stay, since they last the whole day.
    static func withoutFinished(_ events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        let finished = events.filter { !$0.isAllDay && $0.end <= now }
        let keep = finished
            .filter { now.timeIntervalSince($0.end) <= recentlyFinishedWindow }
            .max { ($0.end, $0.start) < ($1.end, $1.start) }
        return events.filter { $0.isAllDay || $0.end > now || $0.id == keep?.id }
    }

    /// Drops copies of the same event that appear in more than one calendar.
    static func deduplicated(_ events: [CalendarEvent]) -> [CalendarEvent] {
        struct Key: Hashable {
            let title: String
            let start: Date
            let end: Date
            let isAllDay: Bool
        }
        var seen = Set<Key>()
        return events.filter { seen.insert(Key(title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)).inserted }
    }

    private static func kind(of date: Date, today: Date, calendar: Calendar) -> AgendaDay.Kind {
        if calendar.isDate(date, inSameDayAs: today) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(date, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        return .other
    }
}
