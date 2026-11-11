import Foundation

/// Which events get an alert before they start.
enum MeetingAlertScope: String, CaseIterable, Identifiable, Sendable {
    case videoMeetings, allEvents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .videoMeetings: "Video meetings"
        case .allEvents: "All events"
        }
    }
}

/// Decides when an event's alert is due. Each occurrence alerts once, from the chosen time before it starts
/// until a few minutes in, so a Mac that wakes just after the start still gets it.
enum MeetingAlertSchedule {

    /// The choices offered in Settings, in minutes before the start. 0 is "when it starts".
    nonisolated static let leadOptions = [0, 1, 2, 5, 10]
    /// How long after the start an alert can still first appear.
    nonisolated static let grace: TimeInterval = 5 * 60

    static func key(_ event: CalendarEvent) -> String {
        "\(event.id)@\(event.start.timeIntervalSinceReferenceDate)"
    }

    static func due(
        _ events: [CalendarEvent], now: Date, leadMinutes: Int, scope: MeetingAlertScope, shown: Set<String>
    ) -> [CalendarEvent] {
        events
            .filter { event in
                !event.isAllDay
                    && event.attendance != .declined
                    && (scope == .allEvents || event.meetingURL != nil)
                    && now >= event.start.addingTimeInterval(-TimeInterval(leadMinutes * 60))
                    && now < min(event.start.addingTimeInterval(grace), event.end)
                    && !shown.contains(key(event))
            }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// "Starts in 2 min", "Starting now" or "Started 3 min ago", to the minute.
    static func timing(of event: CalendarEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded())
        switch minutes {
        case 1...: return "Starts in \(minutes) min"
        case 0: return "Starting now"
        default: return "Started \(-minutes) min ago"
        }
    }
}
