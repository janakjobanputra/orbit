import Foundation
@testable import Orbit

/// In-memory stand-in for EventKit. `linkText` plays the part of an event's URL, location and notes,
/// and goes through the same meeting-link detection the real store uses.
@MainActor
final class FakeEventStore: EventProviding {

    struct Stored {
        var event: CalendarEvent
        var linkText: String?
    }

    var access: EventStoreService.Access = .granted
    var defaultCalendarID: String?
    var calendarList: [CalendarInfo] = []
    var stored: [Stored] = []
    private(set) var created: [(title: String, calendarID: String)] = []

    func add(_ event: CalendarEvent, link: String? = nil) {
        stored.append(Stored(event: event, linkText: link))
    }

    func requestAccess() async -> Bool { access == .granted }

    func calendars() -> [CalendarInfo] { calendarList }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String, location: String?, url: URL?, notes: String?) throws {
        guard calendarList.contains(where: { $0.id == calendarID }) else { throw EventStoreService.StoreError.calendarNotFound }
        created.append((title, calendarID))
        add(CalendarEvent(
            id: UUID().uuidString, title: title, start: start, end: end, isAllDay: isAllDay,
            calendarID: calendarID, color: .fallback, location: location, meetingURL: nil
        ), link: [url?.absoluteString, location, notes].compactMap { $0 }.joined(separator: "\n"))
    }

    func events(from start: Date, to end: Date, extraMeetingHosts: [String]) -> [CalendarEvent] {
        stored
            .filter { $0.event.start < end && $0.event.end > start }
            .map { item in
                var event = item.event
                event.meetingURL = MeetingLinkDetector.firstMeetingURL(in: [item.linkText], extraHosts: extraMeetingHosts)
                event.links = MeetingLinkDetector.otherLinks(in: [item.linkText], extraHosts: extraMeetingHosts)
                return event
            }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    func deleteEvent(_ event: CalendarEvent) throws {
        guard let index = stored.firstIndex(where: { $0.event.id == event.id }) else { throw EventStoreService.StoreError.eventNotFound }
        stored.remove(at: index)
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {}
}

/// Mutable time source so tests can move the clock.
@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
enum StateFixture {

    /// Saturday 31 October 2026, 9:47 UTC — the same moment the formatter tests use.
    nonisolated static let now = TestSupport.date(2026, 10, 31, 9, 47)

    static func calendarInfo(_ id: String, source: String = "iCloud", writable: Bool = true) -> CalendarInfo {
        CalendarInfo(id: id, title: id.capitalized, sourceTitle: source, color: .fallback, isWritable: writable)
    }

    /// AppState over a fake store and throwaway defaults, already loaded.
    static func make(
        at time: Date = now,
        latestRelease: ReleaseInfo? = nil,
        configure: @MainActor (FakeEventStore, Preferences) -> Void = { _, _ in }
    ) async -> (state: AppState, store: FakeEventStore, clock: TestClock) {
        let defaults = UserDefaults(suiteName: "OrbitTests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        let store = FakeEventStore()
        store.calendarList = [calendarInfo("work"), calendarInfo("home")]
        configure(store, preferences)
        let clock = TestClock(time)
        let updates = UpdateChecker(
            currentVersion: AppVersion("1.0.0")!, fetcher: StubReleaseFetcher(release: latestRelease), defaults: defaults
        ) { clock.now }
        let state = AppState(
            preferences: preferences, updates: updates, eventService: store, calendar: TestSupport.calendar()
        ) { clock.now }
        if latestRelease != nil { await updates.checkNow() }
        await state.start()
        state.stop()
        return (state, store, clock)
    }
}

/// Answers update checks with a fixed release, or fails when there is none.
struct StubReleaseFetcher: ReleaseFetching {
    let release: ReleaseInfo?
    struct NoRelease: Error {}
    func latestRelease() async throws -> ReleaseInfo {
        guard let release else { throw NoRelease() }
        return release
    }
}
