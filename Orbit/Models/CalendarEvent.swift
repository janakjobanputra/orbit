import Foundation

struct EventColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback = EventColor(red: 0.6, green: 0.6, blue: 0.6)
}

struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let color: EventColor
    let location: String?
    var meetingURL: URL?
    /// Notes as plain text, with any HTML from the calendar server stripped.
    var notes: String? = nil
    /// Web links other than the meeting link, from the event's URL, location and notes.
    var links: [URL] = []
    var guests: [Guest] = []
    /// EventKit's identifier, used to find this occurrence again to open or delete it.
    var calendarItemID: String? = nil

    /// True when any part of the event falls on the given day.
    func overlaps(day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        if start == end { return start >= dayStart && start < dayEnd }
        return start < dayEnd && end > dayStart
    }

    func isInProgress(at date: Date) -> Bool {
        start <= date && date < end
    }
}

struct Guest: Hashable, Sendable {

    enum Response: Hashable, Sendable {
        case accepted, tentative, declined, pending
    }

    let name: String
    let response: Response
    var isOrganizer = false
    var isYou = false
}

struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: EventColor
    let isWritable: Bool
}
