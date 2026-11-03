import Foundation

/// Where an event sits relative to now, for the "in 6m" and "28m left" pills.
enum EventTiming: Equatable, Sendable {
    case later
    case soon(startsIn: TimeInterval)
    case now(remaining: TimeInterval)
    case ended

    /// How far ahead an upcoming event gets the expanded card.
    static let soonWindow: TimeInterval = 10 * 60

    init(event: CalendarEvent, now: Date) {
        if event.end <= now && event.end > event.start {
            self = .ended
        } else if event.start <= now && now < event.end {
            self = .now(remaining: event.end.timeIntervalSince(now))
        } else if event.start > now && event.start.timeIntervalSince(now) <= Self.soonWindow {
            self = .soon(startsIn: event.start.timeIntervalSince(now))
        } else if event.start <= now {
            self = .ended
        } else {
            self = .later
        }
    }

    /// All-day events never expand; they'd fill the agenda all day.
    static func isHighlighted(_ event: CalendarEvent, now: Date) -> Bool {
        guard !event.isAllDay else { return false }
        switch EventTiming(event: event, now: now) {
        case .soon, .now: return true
        case .later, .ended: return false
        }
    }

    /// "in 6m", "28m left", "Ended", or nil for later events. Minutes round up, so it never says "in 0m".
    var label: String? {
        switch self {
        case .later: nil
        case .soon(let interval): "in \(DurationText.string(Self.wholeMinutes(interval)))"
        case .now(let interval): "\(DurationText.string(Self.wholeMinutes(interval))) left"
        case .ended: "Ended"
        }
    }

    private static func wholeMinutes(_ interval: TimeInterval) -> TimeInterval {
        (interval / 60).rounded(.up) * 60
    }
}

/// Turns the HTML some calendar servers put in notes into plain text.
enum NotesText {

    static func plain(_ notes: String?) -> String? {
        guard var text = notes else { return nil }
        if text.range(of: #"<[a-zA-Z/][^>]*>"#, options: .regularExpression) != nil {
            // Keep the target of each link, since the visible text is often just "Join".
            text = text.replacingOccurrences(of: #"<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, with: "$2 ($1)", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: #"<br\s*/?>|</p>|</div>|</li>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
            for (entity, character) in entities {
                text = text.replacingOccurrences(of: entity, with: character)
            }
            // "https://x (https://x)" when the link text was the address itself.
            text = text.replacingOccurrences(of: #"(https?://\S+) \(\1\)"#, with: "$1", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum GuestSummary {

    /// "3 guests · 2 yes, 1 maybe".
    static func text(_ guests: [Guest]) -> String? {
        guard !guests.isEmpty else { return nil }
        let count = guests.count == 1 ? "1 guest" : "\(guests.count) guests"
        let parts = [
            (Guest.Response.accepted, "yes"),
            (.tentative, "maybe"),
            (.declined, "no"),
            (.pending, "awaiting"),
        ].compactMap { response, word -> String? in
            let n = guests.filter { $0.response == response }.count
            return n == 0 ? nil : "\(n) \(word)"
        }
        return parts.isEmpty ? count : "\(count) · \(parts.joined(separator: ", "))"
    }
}

enum EventCopyText {

    /// The event as a few lines of plain text for the clipboard.
    static func make(_ event: CalendarEvent, calendar: Calendar) -> String {
        var date = Date.FormatStyle(date: .complete, time: .omitted)
        date.timeZone = calendar.timeZone
        var lines = [event.title]
        if event.isAllDay {
            lines.append("\(event.start.formatted(date)) · All day")
        } else {
            var range = Date.IntervalFormatStyle(timeZone: calendar.timeZone).hour().minute()
            if !calendar.isDate(event.start, inSameDayAs: event.end) {
                range = Date.IntervalFormatStyle(date: .abbreviated, time: .shortened, timeZone: calendar.timeZone)
                lines.append((event.start..<event.end).formatted(range))
            } else {
                lines.append("\(event.start.formatted(date)) · \((event.start..<event.end).formatted(range))")
            }
        }
        if let url = event.meetingURL { lines.append("Join: \(url.absoluteString)") }
        if let location = event.location, !location.isEmpty { lines.append("Location: \(location)") }
        lines += event.links.map(\.absoluteString)
        return lines.joined(separator: "\n")
    }
}
