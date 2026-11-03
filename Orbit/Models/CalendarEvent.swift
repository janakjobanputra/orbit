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

    /// Whether you're going, from your own reply to the invitation. Events you organised, or that
    /// aren't invitations at all, count as attending.
    var attendance: Attendance {
        guard let you = guests.first(where: \.isYou), !you.isOrganizer else { return .attending }
        switch you.response {
        case .accepted: return .attending
        case .pending: return .notAnswered
        case .tentative: return .maybe
        case .declined: return .declined
        }
    }
}

/// Your reply to an event, as the agenda and Day view mark it.
enum Attendance: Hashable, Sendable {
    case attending, notAnswered, maybe, declined

    /// Shown next to the event's time; nothing for events you're going to.
    var label: String? {
        switch self {
        case .attending: nil
        case .notAnswered: "Not answered"
        case .maybe: "Maybe"
        case .declined: "Declined"
        }
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
