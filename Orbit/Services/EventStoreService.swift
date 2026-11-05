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
    /// The same events without notes, links or meeting links: enough for the month grid's dots, and much cheaper.
    func eventSummaries(from start: Date, to end: Date) -> [CalendarEvent]
    /// Picks up calendar accounts added or removed since the last call. True when something changed.
    func refresh() -> Bool
    /// Deletes this one occurrence, leaving the rest of a repeating event alone.
    func deleteEvent(_ event: CalendarEvent) throws
    func startObserving(onChange: @escaping @MainActor () -> Void)
}

extension EventProviding {
    func eventSummaries(from start: Date, to end: Date) -> [CalendarEvent] {
        events(from: start, to: end, extraMeetingHosts: [])
    }

    func refresh() -> Bool { false }
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

    private var store = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor () -> Void)?

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
            .map { Self.map($0, extraMeetingHosts: extraMeetingHosts) }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    func eventSummaries(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map { Self.map($0, extraMeetingHosts: [], detailed: false) }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// An `EKEventStore` keeps the accounts it started with: one added later in System Settings › Internet Accounts,
    /// or every account when access was granted after the store was made, can stay missing until the app restarts.
    /// So this looks with a fresh store and switches to it when it sees different calendars.
    func refresh() -> Bool {
        guard access == .granted else { return false }
        store.refreshSourcesIfNecessary()
        let fresh = EKEventStore()
        guard Self.calendarIDs(in: fresh) != Self.calendarIDs(in: store) else { return false }
        store = fresh
        if let onChange { startObserving(onChange: onChange) }
        return true
    }

    private static func calendarIDs(in store: EKEventStore) -> Set<String> {
        Set(store.calendars(for: .event).map(\.calendarIdentifier))
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
        self.onChange = onChange
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach {
            center.removeObserver($0)
            workspace.removeObserver($0)
        }
        let handler: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { onChange() }
        }
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: handler),
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: handler),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: handler),
        ]
    }

    private static func map(_ event: EKEvent, extraMeetingHosts: [String], detailed: Bool = true) -> CalendarEvent {
        let title = event.title ?? ""
        let fields = detailed ? [event.url?.absoluteString, event.location, event.notes] : []
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
            notes: detailed ? NotesText.plain(event.notes) : nil,
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

    private static func color(of calendar: EKCalendar) -> EventColor {
        guard let rgb = calendar.color.usingColorSpace(.sRGB) else { return .fallback }
        return EventColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
