import Foundation

enum EventSearch {

    /// Events whose title or location contains every word of the query, ignoring case and accents.
    static func matches(_ events: [CalendarEvent], query: String) -> [CalendarEvent] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        return events.filter { event in
            let text = [event.title, event.location ?? ""].joined(separator: " ")
            return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Upcoming events first, soonest first; then past events, most recent first.
    static func ranked(_ events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        let upcoming = events.filter { $0.end > now }.sorted { $0.start < $1.start }
        let past = events.filter { $0.end <= now }.sorted { $0.start > $1.start }
        return upcoming + past
    }
}

enum NewEventDraft {

    static let defaultDuration: TimeInterval = 30 * 60

    /// Today: the next half hour. Any other day: 9am.
    static func defaultStart(on day: Date, now: Date, calendar: Calendar) -> Date {
        guard calendar.isDate(day, inSameDayAs: now) else {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        guard let hour = calendar.dateInterval(of: .hour, for: now)?.start else { return now }
        let minute = calendar.component(.minute, from: now)
        return hour.addingTimeInterval(minute < 30 ? 30 * 60 : 60 * 60)
    }

    static func isValid(title: String, start: Date, end: Date) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }

    /// Trimmed text, or nil when the field was left empty.
    static func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A link typed into the form. "zoom.us/j/1" gets https:// added; anything that isn't a web address is nil.
    static func link(from text: String) -> URL? {
        guard let trimmed = optional(text), !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host?.contains(".") == true,
              ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
}
