import Foundation

/// Builds the menu bar title from the chosen tokens, joined by the chosen separator.
struct MenuBarFormatter {

    var format: MenuBarFormat
    var leadMinutes: Int
    var maxTitleLength = 24
    var locale: Locale = .current
    var calendar: Calendar = .autoupdatingCurrent

    func title(now: Date, events: [CalendarEvent]) -> String {
        let parts = format.tokens.compactMap { text(for: $0, now: now, events: events) }
        // A title that would be empty (e.g. Agenda with nothing coming up) falls back to date and time.
        guard !parts.isEmpty else {
            return [dateText(now), timeText(now)].joined(separator: format.separator.joiner)
        }
        return parts.joined(separator: format.separator.joiner)
    }

    func text(for token: MenuBarToken, now: Date, events: [CalendarEvent]) -> String? {
        switch token {
        case .date: dateText(now)
        case .time: timeText(now)
        case .nextEvent: eventText(now: now, events: events)
        case .weekNumber: "W\(calendar.component(.weekOfYear, from: now))"
        }
    }

    func dateText(_ date: Date) -> String {
        string(from: date, pattern: format.datePattern, fallback: MenuBarFormat.defaultDatePattern)
    }

    func timeText(_ date: Date) -> String {
        string(from: date, pattern: format.timePattern, fallback: MenuBarFormat.defaultTimePattern)
    }

    /// An event starting within the lead time wins over one already in progress.
    func eventText(now: Date, events: [CalendarEvent]) -> String? {
        let timed = events.filter { !$0.isAllDay }

        if let next = timed.filter({ $0.start > now }).min(by: { $0.start < $1.start }) {
            let minutes = Self.minutes(from: now, to: next.start)
            if minutes <= leadMinutes {
                return "\(shortened(next.title)) in \(minutes)m"
            }
        }

        if let current = timed.filter({ $0.isInProgress(at: now) }).min(by: { $0.end < $1.end }) {
            return "\(shortened(current.title)) · \(Self.minutes(from: now, to: current.end))m left"
        }

        return nil
    }

    /// Whole minutes remaining, rounded up so "in 0m" never appears.
    static func minutes(from now: Date, to date: Date) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    private func string(from date: Date, pattern: String, fallback: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : pattern
        return formatter.string(from: date)
    }

    private func shortened(_ title: String) -> String {
        guard title.count > maxTitleLength else { return title }
        return title.prefix(maxTitleLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
