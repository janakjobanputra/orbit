import Foundation

/// Made-up calendars and events for the Settings preview, so it shows every feature without your own events.
/// Everything is laid out around the moment it's created: a meeting in progress, one that just ended, more
/// later today, all-day events, an overnight flight, and events spread over the surrounding weeks.
@MainActor
final class DemoEventStore: EventProviding {

    let access: EventStoreService.Access = .granted
    let defaultCalendarID: String? = DemoCalendar.work.rawValue
    private var events: [CalendarEvent]

    init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        events = Self.makeEvents(now: now, calendar: calendar)
    }

    func requestAccess() async -> Bool { true }

    func calendars() -> [CalendarInfo] {
        DemoCalendar.allCases.map {
            CalendarInfo(id: $0.rawValue, title: $0.title, sourceTitle: "Demo", color: $0.color, isWritable: $0 != .holidays)
        }
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, location: String?, url: URL?, notes: String?) throws {
        var event = CalendarEvent(
            id: UUID().uuidString, title: title, start: start, end: end, isAllDay: isAllDay,
            calendarID: calendarID, color: DemoCalendar(rawValue: calendarID)?.color ?? .fallback,
            location: location, meetingURL: url.flatMap { MeetingLinkDetector.isMeetingURL($0) ? $0 : nil }
        )
        event.notes = notes
        event.calendarItemID = event.id
        events.append(event)
    }

    func events(from start: Date, to end: Date, extraMeetingHosts: [String]) -> [CalendarEvent] {
        events
            .filter { $0.start < end && $0.end > start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    func deleteEvent(_ event: CalendarEvent) throws {
        events.removeAll { $0.id == event.id }
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {}

    // MARK: - Sample data

    private static func makeEvents(now: Date, calendar: Calendar) -> [CalendarEvent] {
        let today = calendar.startOfDay(for: now)
        // Anchor today's timed events to the clock, on a five-minute grid, so "in progress" is always true.
        let minute = calendar.component(.minute, from: now)
        let anchor = calendar.date(byAdding: .minute, value: -(minute % 5), to: now) ?? now
        func at(_ minutes: Int) -> Date { anchor.addingTimeInterval(TimeInterval(minutes * 60)) }
        func day(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }

        var result: [CalendarEvent] = []
        func add(
            _ title: String, _ start: Date, _ end: Date, _ demo: DemoCalendar, allDay: Bool = false,
            location: String? = nil, meeting: String? = nil, links: [String] = [], notes: String? = nil,
            guests: [Guest] = []
        ) {
            var event = CalendarEvent(
                id: "demo-\(result.count)", title: title, start: start, end: end, isAllDay: allDay,
                calendarID: demo.rawValue, color: demo.color, location: location, meetingURL: meeting.flatMap(URL.init(string:))
            )
            event.links = links.compactMap(URL.init(string:))
            event.notes = notes
            event.guests = guests
            event.calendarItemID = event.id
            result.append(event)
        }

        // Today
        add("Product launch week", day(0), day(1), .work, allDay: true)
        add("Mia's birthday", day(0), day(1), .family, allDay: true)
        add("Gym", at(-240), at(-180), .personal, location: "Equinox")
        add("Morning standup", at(-80), at(-20), .work, meeting: "https://meet.google.com/abc-defg-hij")
        add(
            "Design review", at(-15), at(30), .work,
            location: "Studio 3",
            meeting: "https://meet.google.com/xyz-pqrs-tuv",
            links: ["https://www.figma.com/file/orbit-v1"],
            notes: "Walk through the new popover and Settings. Mockups: https://www.figma.com/file/orbit-v1",
            guests: [
                Guest(name: "You", response: .accepted, isOrganizer: true, isYou: true),
                Guest(name: "Priya Shah", response: .accepted),
                Guest(name: "Sam Lee", response: .tentative),
                Guest(name: "Alex Kim", response: .pending),
            ]
        )
        add("Focus time", at(60), at(120), .work)
        add("1:1 with Sam", at(150), at(180), .work, meeting: "https://zoom.us/j/5550123456")
        add("Coffee with Priya", at(240), at(285), .personal, location: "Blue Bottle, Hayes Valley")

        // Tomorrow and the rest of the week
        add("Day off", day(1), day(2), .personal, allDay: true)
        add("Flight to Lisbon", day(1, 18, 40), day(2, 10, 25), .personal, location: "SFO Terminal 2")
        add("Dentist", day(2, 9), day(2, 10), .family, location: "Mission Dental")
        add("Sprint planning", day(3, 10), day(3, 11), .work, meeting: "https://teams.microsoft.com/l/meetup-join/demo")
        add("Book club", day(3, 19), day(3, 21), .personal)
        add("Public holiday", day(4), day(5), .holidays, allDay: true)
        add("Climbing", day(5, 18, 30), day(5, 20), .personal, location: "Mission Cliffs")
        add("School pickup", day(6, 15), day(6, 15, 30), .family)

        // Scattered over the surrounding weeks, so the month grid has dots in every color
        let spread: [(Int, Int, String, DemoCalendar)] = [
            (-20, 9, "Quarterly review", .work), (-17, 18, "Dinner with Jo", .personal),
            (-15, 10, "Vet appointment", .family), (-12, 14, "Hiring panel", .work),
            (-10, 8, "Run club", .personal), (-8, 11, "Roadmap sync", .work),
            (-6, 16, "Parent–teacher meeting", .family), (-4, 12, "Lunch and learn", .work),
            (-2, 19, "Movie night", .personal), (-1, 10, "Retro", .work),
            (8, 9, "Board prep", .work), (9, 17, "Soccer practice", .family),
            (11, 13, "Customer call", .work), (12, 19, "Concert", .personal),
            (14, 10, "All hands", .work), (16, 11, "Haircut", .personal),
            (18, 9, "Offsite planning", .work), (20, 15, "Recital", .family),
            (23, 10, "Design crit", .work), (25, 18, "Dinner party", .personal),
        ]
        for (offset, hour, title, demo) in spread {
            add(title, day(offset, hour), day(offset, hour + 1), demo)
            // A second event on some days, so several dots share a day.
            if offset % 3 == 0 {
                add("Check-in", day(offset, hour + 2), day(offset, hour + 2, 30), .work)
            }
        }
        return result
    }
}

enum DemoCalendar: String, CaseIterable {
    case work = "demo-work", personal = "demo-personal", family = "demo-family", holidays = "demo-holidays"

    var title: String {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        case .family: "Family"
        case .holidays: "Holidays"
        }
    }

    var color: EventColor {
        switch self {
        case .work: EventColor(red: 0.22, green: 0.52, blue: 0.98)
        case .personal: EventColor(red: 0.20, green: 0.70, blue: 0.42)
        case .family: EventColor(red: 0.85, green: 0.33, blue: 0.62)
        case .holidays: EventColor(red: 0.96, green: 0.56, blue: 0.20)
        }
    }
}
