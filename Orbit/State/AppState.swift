import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    /// What the popover is showing below its header.
    enum Mode {
        case agenda, search, newEvent
    }

    let preferences: Preferences
    @ObservationIgnored private let eventService: any EventProviding
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let baseCalendar: Calendar
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    private(set) var access: EventStoreService.Access = .notDetermined
    private(set) var now: Date
    private(set) var calendars: [CalendarInfo] = []
    private(set) var systemDefaultCalendarID: String?
    private var gridEvents: [CalendarEvent] = []
    private var agendaEvents: [CalendarEvent] = []
    private var nearbyEvents: [CalendarEvent] = []
    private var searchPool: [CalendarEvent] = []

    var mode: Mode = .agenda
    var searchQuery = ""
    /// The event whose detail popout is open, if any.
    var detailEventID: String?

    var displayedMonth: Date {
        didSet { reload() }
    }
    var selectedDate: Date {
        didSet {
            if !calendar.isDate(oldValue, inSameDayAs: selectedDate) { reloadAgenda() }
        }
    }

    init(
        preferences: Preferences = Preferences(),
        eventService: any EventProviding = EventStoreService(),
        calendar: Calendar = .autoupdatingCurrent,
        clock: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.eventService = eventService
        self.baseCalendar = calendar
        self.clock = clock
        let start = clock()
        now = start
        displayedMonth = start
        selectedDate = start
    }

    // MARK: - Lifecycle

    func start() async {
        access = eventService.access
        if access == .notDetermined {
            access = await eventService.requestAccess() ? .granted : .denied
        }
        eventService.startObserving { [weak self] in
            guard let self else { return }
            self.now = self.clock()
            self.reload()
        }
        reload()
        startTicking()
    }

    func requestAccess() async {
        access = await eventService.requestAccess() ? .granted : eventService.access
        reload()
    }

    func stop() {
        tickTask?.cancel()
    }

    // MARK: - Derived data

    /// The current calendar with the user's chosen first weekday.
    var calendar: Calendar {
        var calendar = baseCalendar
        calendar.firstWeekday = preferences.weekStart.rawValue
        return calendar
    }

    var gridDays: [CalendarDay] {
        MonthGrid.days(for: displayedMonth, calendar: calendar)
    }

    var menuBarTitle: String {
        MenuBarFormatter(format: preferences.menuBarFormat, leadMinutes: preferences.nextEventLeadMinutes, calendar: calendar)
            .title(now: now, events: visible(nearbyEvents))
    }

    var daySummary: DaySummary {
        DaySummary(events: Agenda.deduplicated(visible(nearbyEvents)), day: now, calendar: calendar)
    }

    var agendaDays: [AgendaDay] {
        let events = Agenda.deduplicated(visible(agendaEvents))
            .filter { !(preferences.hidePastEvents && $0.end <= now) }
        return Agenda.days(
            from: selectedDate,
            count: preferences.agendaDayCount,
            events: events,
            now: now,
            calendar: calendar,
            includeEmptyDays: !preferences.hideEmptyDays
        )
        .map { day in
            guard day.kind == .today else { return day }
            return AgendaDay(date: day.date, kind: day.kind, events: Agenda.withoutFinished(day.events, now: now))
        }
    }

    func agendaRows(for day: AgendaDay) -> [AgendaRow] {
        let gaps = preferences.showFreeTime
            ? BusyTime.freeGaps(in: day.events, on: day.date, now: now, calendar: calendar)
            : []
        return Agenda.rows(events: day.events, gaps: gaps, now: day.kind == .today ? now : nil)
    }

    var searchResults: [CalendarEvent] {
        EventSearch.ranked(EventSearch.matches(Agenda.deduplicated(visible(searchPool)), query: searchQuery), now: now)
    }

    var writableCalendars: [CalendarInfo] {
        calendars.filter(\.isWritable)
    }

    /// The user's chosen calendar for new events when it is still writable, else the system default.
    var defaultCalendarID: String? {
        let writable = writableCalendars.map(\.id)
        if let chosen = preferences.defaultCalendarID, writable.contains(chosen) { return chosen }
        if let system = systemDefaultCalendarID, writable.contains(system) { return system }
        return writable.first
    }

    /// The meeting in progress, or the next one with a video link in the coming 12 hours.
    var nextMeetingURL: URL? {
        visible(nearbyEvents)
            .filter { !$0.isAllDay && $0.meetingURL != nil && $0.end > now && $0.start < now.addingTimeInterval(12 * 3600) }
            .min { $0.start < $1.start }?
            .meetingURL
    }

    func events(on day: Date) -> [CalendarEvent] {
        visible(gridEvents).filter { $0.overlaps(day: day, calendar: calendar) }
    }

    /// Up to three distinct calendar colours for the dots under a day.
    func eventColors(on day: Date) -> [EventColor] {
        var seen: [EventColor] = []
        for event in events(on: day) where !seen.contains(event.color) {
            seen.append(event.color)
            if seen.count == 3 { break }
        }
        return seen
    }

    // MARK: - Actions

    func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
    }

    func showToday() {
        now = clock()
        show(date: now)
    }

    /// Escape closes the innermost thing first: the event detail, then the popover itself.
    /// Returns false when there was nothing left inside to close, so the caller should close the popover.
    func handleEscape() -> Bool {
        if detailEventID != nil {
            detailEventID = nil
            return true
        }
        return false
    }

    /// Selects a day, brings its month into view and returns to the agenda.
    func show(date: Date) {
        mode = .agenda
        selectedDate = date
        if !calendar.isDate(displayedMonth, equalTo: date, toGranularity: .month) {
            displayedMonth = date
        }
    }

    func beginSearch() {
        searchQuery = ""
        if access == .granted {
            searchPool = fetch(from: now.addingTimeInterval(-90 * 86_400), to: now.addingTimeInterval(365 * 86_400))
        }
        mode = .search
    }

    func beginNewEvent() {
        mode = .newEvent
    }

    func returnToAgenda() {
        mode = .agenda
        searchQuery = ""
    }

    func createEvent(
        title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String,
        location: String? = nil, url: URL? = nil, notes: String? = nil
    ) throws {
        try eventService.createEvent(
            title: title, start: start, end: end, isAllDay: isAllDay, calendarID: calendarID,
            location: location, url: url, notes: notes
        )
        reload()
        show(date: start)
    }

    /// Reads the clock now rather than waiting for the next minute tick.
    func refreshNow() {
        now = clock()
    }

    func joinNextMeeting() {
        refreshNow()
        if let url = nextMeetingURL {
            NSWorkspace.shared.open(url)
        } else {
            NSSound.beep()
        }
    }

    func calendarInfo(for event: CalendarEvent) -> CalendarInfo? {
        calendars.first { $0.id == event.calendarID }
    }

    func canDelete(_ event: CalendarEvent) -> Bool {
        calendarInfo(for: event)?.isWritable == true && event.calendarItemID != nil
    }

    func deleteEvent(_ event: CalendarEvent) throws {
        try eventService.deleteEvent(event)
        reload()
    }

    /// Shows the event in Apple Calendar.
    func openInCalendar(_ event: CalendarEvent) {
        let url = event.calendarItemID
            .flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            .flatMap { URL(string: "ical://ekevent/\($0)?method=show&options=more") }
        if let url, NSWorkspace.shared.open(url) { return }
        if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openInMaps(_ location: String) {
        if let url = preferences.mapsProvider.url(for: location) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Loading

    func reload() {
        guard access == .granted else {
            gridEvents = []
            agendaEvents = []
            nearbyEvents = []
            return
        }
        calendars = eventService.calendars()
        systemDefaultCalendarID = eventService.defaultCalendarID
        // The grid shows up to a week either side of the month, whichever day the week starts on.
        if let month = calendar.dateInterval(of: .month, for: displayedMonth) {
            gridEvents = fetch(from: month.start.addingTimeInterval(-7 * 86_400), to: month.end.addingTimeInterval(14 * 86_400))
        }
        let today = calendar.startOfDay(for: now)
        nearbyEvents = fetch(from: today, to: today.addingTimeInterval(2 * 86_400))
        reloadAgenda()
    }

    /// Loads the longest agenda the settings allow, so changing the length needs no refetch.
    private func reloadAgenda() {
        guard access == .granted else { return }
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: Preferences.maxAgendaDayCount, to: start) else { return }
        agendaEvents = fetch(from: start, to: end)
    }

    private func fetch(from start: Date, to end: Date) -> [CalendarEvent] {
        eventService.events(from: start, to: end, extraMeetingHosts: preferences.customMeetingHosts)
    }

    private func visible(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let keywords = TitleFilter.keywords(from: preferences.ignoredTitleKeywords)
        return events.filter { event in
            preferences.isCalendarVisible(event.calendarID)
                && !(preferences.hideAllDayEvents && event.isAllDay)
                && !TitleFilter.isIgnored(event.title, keywords: keywords)
        }
    }

    /// Wakes at the top of each minute so the menu bar clock stays exact.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let current = self?.clock() ?? Date()
                let next = Calendar.current.nextDate(after: current, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
                    ?? current.addingTimeInterval(60)
                try? await Task.sleep(for: .seconds(next.timeIntervalSince(current)))
                guard let self else { return }
                let previous = self.now
                self.now = self.clock()
                if !self.calendar.isDate(previous, inSameDayAs: self.now) || self.now.timeIntervalSince(previous) > 120 {
                    self.reload()
                }
            }
        }
    }
}
