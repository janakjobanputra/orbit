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
    let updates: UpdateState
    @ObservationIgnored private let eventService: any EventProviding
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let baseCalendar: Calendar
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    private(set) var access: EventStoreService.Access = .notDetermined
    /// The time the calendar shows, moved on each minute.
    private(set) var now: Date {
        didSet { menuBarNow = now }
    }
    /// The time the menu bar shows: the same as `now`, but moved every second when the title includes seconds.
    private(set) var menuBarNow: Date
    private(set) var calendars: [CalendarInfo] = []
    private(set) var systemDefaultCalendarID: String?
    /// The month grid's events, filed under each day they touch, so drawing 42 days doesn't scan every event 42 times.
    private var gridEventsByDay: [Date: [CalendarEvent]] = [:]
    private var agendaEvents: [CalendarEvent] = []
    private var nearbyEvents: [CalendarEvent] = []
    private var searchPool: [CalendarEvent] = []

    var mode: Mode = .agenda
    var searchQuery = ""
    /// The event whose detail popout is open, if any.
    var detailEventID: String?

    /// The day the calendar grid is built around: any day of the month it shows, or the middle of its three weeks.
    var displayedMonth: Date {
        didSet {
            let sameMonth = calendar.isDate(oldValue, equalTo: displayedMonth, toGranularity: .month)
            let sameWeek = calendar.isDate(oldValue, equalTo: displayedMonth, toGranularity: .weekOfYear)
            if !(sameMonth && sameWeek) { reloadGrid() }
        }
    }
    var selectedDate: Date {
        didSet {
            if !calendar.isDate(oldValue, inSameDayAs: selectedDate) { reloadAgenda() }
        }
    }

    init(
        preferences: Preferences = Preferences(),
        updates: UpdateState = UpdateState(),
        eventService: any EventProviding = EventStoreService(),
        calendar: Calendar = .autoupdatingCurrent,
        clock: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.updates = updates
        self.eventService = eventService
        self.baseCalendar = calendar
        self.clock = clock
        let start = clock()
        menuBarNow = start
        now = start
        displayedMonth = start
        selectedDate = start
    }

    // MARK: - Lifecycle

    /// Opens the welcome tour. Set by the app; does nothing in tests and previews.
    @ObservationIgnored var showWelcomeTour: @MainActor () -> Void = {}

    /// `askForAccess: false` leaves the calendar permission question for the welcome tour to ask.
    func start(askForAccess: Bool = true) async {
        access = eventService.access
        if askForAccess, access == .notDetermined {
            access = await eventService.requestAccess() ? .granted : .denied
        }
        eventService.startObserving { [weak self] in
            guard let self else { return }
            self.now = self.clock()
            if !self.refreshCalendars() { self.reload() }
        }
        reload()
        startTicking()
    }

    func requestAccess() async {
        access = await eventService.requestAccess() ? .granted : eventService.access
        reload()
    }

    /// Catches what changed outside Orbit since it last looked: calendar access turned on in System Settings,
    /// or an account added in Internet Accounts. Runs when the calendar or Settings opens and when calendars change.
    /// Reloads, and returns true, only when something did change.
    @discardableResult
    func refreshCalendars() -> Bool {
        let previous = access
        access = eventService.access
        let changed = eventService.refresh() || access != previous
        if changed { reload() }
        return changed
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Derived data

    /// The current calendar with the user's chosen first weekday.
    var calendar: Calendar {
        var calendar = baseCalendar
        calendar.firstWeekday = preferences.weekStart.rawValue
        return calendar
    }

    var gridDays: [CalendarDay] {
        MonthGrid.days(for: displayedMonth, span: preferences.calendarSpan, calendar: calendar)
    }

    var menuBarTitle: String {
        MenuBarFormatter(format: preferences.menuBarFormat, leadMinutes: preferences.nextEventLeadMinutes, calendar: calendar)
            .title(now: menuBarNow, events: visible(nearbyEvents).filter { $0.attendance != .declined })
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

    /// The selected day for the Day view, with every event that day, finished or not.
    var dayTimeline: DayTimeline {
        DayTimeline(events: Agenda.deduplicated(visible(agendaEvents)), day: selectedDate, calendar: calendar)
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
            .filter { $0.attendance != .declined && !$0.isAllDay && $0.meetingURL != nil && $0.end > now && $0.start < now.addingTimeInterval(12 * 3600) }
            .min { $0.start < $1.start }?
            .meetingURL
    }

    func events(on day: Date) -> [CalendarEvent] {
        visible(gridEventsByDay[calendar.startOfDay(for: day)] ?? [])
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

    /// The arrows: a month at a time, or a week at a time in the 3-week view.
    func showPage(offset: Int) {
        guard let date = calendar.date(byAdding: preferences.calendarSpan.pageComponent, value: offset, to: displayedMonth) else { return }
        displayedMonth = date
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
        // The 3-week view puts the day's week in the middle; the month view only moves if it's another month.
        if !calendar.isDate(displayedMonth, equalTo: date, toGranularity: preferences.calendarSpan.pageComponent) {
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
            calendars = []
            gridEventsByDay = [:]
            agendaEvents = []
            nearbyEvents = []
            return
        }
        calendars = eventService.calendars()
        systemDefaultCalendarID = eventService.defaultCalendarID
        reloadGrid()
        let today = calendar.startOfDay(for: now)
        nearbyEvents = fetch(from: today, to: today.addingTimeInterval(2 * 86_400))
        reloadAgenda()
    }

    /// Only the grid changes when you page through it, and it only needs each event's day and colour.
    private func reloadGrid() {
        guard access == .granted else { return }
        // Covers both the month and the 3 weeks around the displayed day, whichever day the week starts on,
        // so switching between them, or changing the first weekday, needs no refetch.
        let dates = (MonthGrid.days(for: displayedMonth, span: .month, calendar: calendar)
            + MonthGrid.days(for: displayedMonth, span: .threeWeeks, calendar: calendar)).map(\.date)
        guard let first = dates.min(), let last = dates.max(),
              let start = calendar.date(byAdding: .day, value: -6, to: first),
              let end = calendar.date(byAdding: .day, value: 7, to: last) else { return }
        var byDay: [Date: [CalendarEvent]] = [:]
        for event in eventService.eventSummaries(from: start, to: end) {
            // The days an event touches run on from the one it starts on.
            var day = max(calendar.startOfDay(for: event.start), start)
            while day < end, event.overlaps(day: day, calendar: calendar) {
                byDay[day, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        gridEventsByDay = byDay
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
                && (preferences.showDeclinedEvents || event.attendance != .declined)
        }
    }

    /// Wakes at the top of each minute, or each second while the menu bar shows seconds, so the clock stays exact.
    /// Starts over whenever the menu bar format changes, so turning seconds on takes effect straight away.
    private func startTicking() {
        tickTask?.cancel()
        withObservationTracking {
            _ = preferences.menuBarFormat
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.tickTask != nil else { return }
                self.startTicking()
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let current = self?.clock(), let showsSeconds = self?.preferences.menuBarFormat.showsSeconds else { return }
                let next = Self.nextTick(after: current, showsSeconds: showsSeconds)
                try? await Task.sleep(for: .seconds(next.timeIntervalSince(current)))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    /// Moves the clock forward: the calendar on each new minute, the menu bar every second if it shows seconds.
    func tick() {
        let current = clock()
        if calendar.isDate(current, equalTo: now, toGranularity: .minute) {
            if preferences.menuBarFormat.showsSeconds { menuBarNow = current }
            return
        }
        let previous = now
        now = current
        // Every quarter hour, so a newly added account reaches the menu bar even if the calendar isn't opened.
        let checkCalendars = calendar.component(.minute, from: now) % 15 == 0 || eventService.access != access
        if checkCalendars, refreshCalendars() { return }
        if !calendar.isDate(previous, inSameDayAs: now) || now.timeIntervalSince(previous) > 120 {
            reload()
        }
    }

    /// The next whole second, or the start of the next minute.
    nonisolated static func nextTick(after date: Date, showsSeconds: Bool, calendar: Calendar = .current) -> Date {
        if showsSeconds {
            return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate + 1).rounded(.down))
        }
        return calendar.nextDate(after: date, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(60)
    }
}
