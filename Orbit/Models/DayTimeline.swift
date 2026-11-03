import Foundation

/// Which list the popover shows under the month: the agenda of days ahead, or one day as a timeline.
enum EventsView: String, CaseIterable, Identifiable, Sendable {
    case agenda, day

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agenda: "Agenda"
        case .day: "Day"
        }
    }
}

/// One day laid out like Calendar's day view: all-day events on top, timed events placed by the minute,
/// with overlapping events sharing the width side by side.
struct DayTimeline {

    struct Block: Identifiable, Equatable {
        let event: CalendarEvent
        /// Minutes from midnight, clipped to the day. Short events are stretched to `minimumMinutes`.
        let startMinute: Int
        let endMinute: Int
        /// Which of `columns` side-by-side slots the block takes.
        let column: Int
        let columns: Int

        var id: String { event.id }
    }

    /// The shortest block drawn, so a 5-minute event still has room for its title.
    static let minimumMinutes = 15

    let allDay: [CalendarEvent]
    let blocks: [Block]

    init(events: [CalendarEvent], day: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let dayLength = Int(end.timeIntervalSince(start) / 60)
        let onDay = events.filter { $0.start < end && $0.end > start }
        allDay = onDay.filter(\.isAllDay)

        let spans = onDay
            .filter { !$0.isAllDay }
            .map { event -> (event: CalendarEvent, start: Int, end: Int) in
                let from = max(0, Int(event.start.timeIntervalSince(start) / 60))
                let to = min(dayLength, Int(event.end.timeIntervalSince(start) / 60))
                return (event, from, min(dayLength, max(to, from + Self.minimumMinutes)))
            }
            .sorted { ($0.start, -$0.end, $0.event.title) < ($1.start, -$1.end, $1.event.title) }

        // Events that overlap, directly or through each other, form a cluster that splits the width.
        var blocks: [Block] = []
        var cluster: [(span: (event: CalendarEvent, start: Int, end: Int), column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func closeCluster() {
            blocks += cluster.map {
                Block(event: $0.span.event, startMinute: $0.span.start, endMinute: $0.span.end, column: $0.column, columns: columnEnds.count)
            }
            cluster = []
            columnEnds = []
        }

        for span in spans {
            if !cluster.isEmpty && span.start >= clusterEnd { closeCluster() }
            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.end
                cluster.append((span, free))
            } else {
                columnEnds.append(span.end)
                cluster.append((span, columnEnds.count - 1))
            }
            clusterEnd = cluster.count == 1 ? span.end : max(clusterEnd, span.end)
        }
        closeCluster()
        self.blocks = blocks
    }
}
