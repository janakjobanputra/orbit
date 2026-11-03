import AppKit
import EventKit

/// Where AppState gets calendars and events from. EventKit in the app, a fake in tests.
@MainActor
protocol EventProviding: AnyObject {
    var access: EventStoreService.Access { get }
    var defaultCalendarID: String? { get }
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, location: String?, url: URL?, notes: String?) throws
    func events(from start: Date, to end: Date, extraMeetingHosts: [String]) -> [CalendarEvent]
    /// Deletes this one occurrence, leaving the rest of a repeating event alone.
    func deleteEvent(_ event: CalendarEvent) throws
    func startObserving(onChange: @escaping @MainActor () -> Void)
}

@MainActor
final class EventStoreService: EventProviding {

    enum Access {
        case notDetermined, granted, denied
    }

    enum StoreError: LocalizedError {
        case calendarNotFound
        case eventNotFound

        var errorDescription: String? {
            switch self {
            case .calendarNotFound: "That calendar is no longer available."
            case .eventNotFound: "That event has already been changed or removed."
            }
        }
    }

    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map {
                CalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title,
                    color: Self.color(of: $0),
                    isWritable: $0.allowsContentModifications
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    var defaultCalendarID: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, location: String?, url: URL?, notes: String?) throws {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw StoreError.calendarNotFound }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = isAllDay
        event.calendar = calendar
        event.location = location
        event.url = url
        event.notes = notes
        try store.save(event, span: .thisEvent, commit: true)
    }

    func events(from start: Date, to end: Date, extraMeetingHosts: [String] = []) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !Self.isDeclined($0) }
            .map { Self.map($0, extraMeetingHosts: extraMeetingHosts) }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    func deleteEvent(_ event: CalendarEvent) throws {
        guard let occurrence = occurrence(of: event) else { throw StoreError.eventNotFound }
        try store.remove(occurrence, span: .thisEvent, commit: true)
    }

    /// The EventKit occurrence behind an event, found by identifier and start so repeats resolve to the right day.
    func occurrence(of event: CalendarEvent) -> EKEvent? {
        guard let id = event.calendarItemID else { return nil }
        let predicate = store.predicateForEvents(withStart: event.start.addingTimeInterval(-1), end: event.end.addingTimeInterval(1), calendars: nil)
        return store.events(matching: predicate).first { $0.calendarItemIdentifier == id && $0.startDate == event.start }
    }

    /// Calls `onChange` when calendar data changes, the day rolls over, or the Mac wakes.
    func startObserving(onChange: @escaping @MainActor () -> Void) {
        let handler: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { onChange() }
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: handler),
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: handler),
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler),
        ]
    }

    private static func map(_ event: EKEvent, extraMeetingHosts: [String]) -> CalendarEvent {
        let title = event.title ?? ""
        let fields = [event.url?.absoluteString, event.location, event.notes]
        return CalendarEvent(
            id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
            title: title.isEmpty ? "Untitled" : title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            color: color(of: event.calendar),
            location: event.location,
            meetingURL: MeetingLinkDetector.firstMeetingURL(in: fields, extraHosts: extraMeetingHosts),
            notes: NotesText.plain(event.notes),
            links: MeetingLinkDetector.otherLinks(in: fields, extraHosts: extraMeetingHosts),
            guests: (event.attendees ?? []).map(guest),
            calendarItemID: event.calendarItemIdentifier
        )
    }

    private static func guest(_ participant: EKParticipant) -> Guest {
        let response: Guest.Response = switch participant.participantStatus {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        default: .pending
        }
        let email = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        return Guest(
            name: participant.name ?? email,
            response: response,
            isOrganizer: participant.participantRole == .chair,
            isYou: participant.isCurrentUser
        )
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private static func color(of calendar: EKCalendar) -> EventColor {
        guard let rgb = calendar.color.usingColorSpace(.sRGB) else { return .fallback }
        return EventColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
