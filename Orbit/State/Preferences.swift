import Foundation
import Observation

/// User settings, persisted to UserDefaults on every change.
@MainActor
@Observable
final class Preferences {

    nonisolated static let agendaDayOptions = [1, 2, 3, 5, 7, 14, 30]
    nonisolated static let maxAgendaDayCount = 30

    private enum Key {
        static let keepCalendarOnTop = "keepCalendarOnTop"
        static let appearance = "appearance"
        static let globalShortcutsEnabled = "globalShortcutsEnabled"
        static let customVideoServices = "customVideoServices"
        static let checkForUpdates = "checkForUpdates"
        static let menuBarFormat = "menuBarFormat"
        static let nextEventLeadMinutes = "nextEventLeadMinutes"
        static let showDaySummary = "showDaySummary"
        static let showFreeTime = "showFreeTime"
        static let showYearProgress = "showYearProgress"
        static let showDayProgress = "showDayProgress"
        static let showWeekNumbers = "showWeekNumbers"
        static let highlightToday = "highlightToday"
        static let dimWeekends = "dimWeekends"
        static let eventDots = "eventDots"
        static let weekStart = "weekStart"
        static let showMonthGrid = "showMonthGrid"
        static let textSize = "textSize"
        static let calendarDensity = "calendarDensity"
        static let eventDensity = "eventDensity"
        static let agendaDayCount = "agendaDayCount"
        static let hideEmptyDays = "hideEmptyDays"
        static let hideAllDayEvents = "hideAllDayEvents"
        static let hidePastEvents = "hidePastEvents"
        static let defaultCalendarID = "defaultCalendarID"
        static let ignoredTitleKeywords = "ignoredTitleKeywords"
        static let mapsProvider = "mapsProvider"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General

    var keepCalendarOnTop: Bool { didSet { defaults.set(keepCalendarOnTop, forKey: Key.keepCalendarOnTop) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var globalShortcutsEnabled: Bool { didSet { defaults.set(globalShortcutsEnabled, forKey: Key.globalShortcutsEnabled) } }
    var customVideoServices: [CustomVideoService] { didSet { store(customVideoServices, forKey: Key.customVideoServices) } }
    /// Look for a new version on GitHub once a day.
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Key.checkForUpdates) } }

    // MARK: Menu bar

    var menuBarFormat: MenuBarFormat { didSet { store(menuBarFormat, forKey: Key.menuBarFormat) } }
    var nextEventLeadMinutes: Int { didSet { defaults.set(nextEventLeadMinutes, forKey: Key.nextEventLeadMinutes) } }

    // MARK: Calendar display

    var showDaySummary: Bool { didSet { defaults.set(showDaySummary, forKey: Key.showDaySummary) } }
    var showFreeTime: Bool { didSet { defaults.set(showFreeTime, forKey: Key.showFreeTime) } }
    var showYearProgress: Bool { didSet { defaults.set(showYearProgress, forKey: Key.showYearProgress) } }
    var showDayProgress: Bool { didSet { defaults.set(showDayProgress, forKey: Key.showDayProgress) } }
    var showWeekNumbers: Bool { didSet { defaults.set(showWeekNumbers, forKey: Key.showWeekNumbers) } }
    var highlightToday: Bool { didSet { defaults.set(highlightToday, forKey: Key.highlightToday) } }
    var dimWeekends: Bool { didSet { defaults.set(dimWeekends, forKey: Key.dimWeekends) } }
    var eventDots: EventDotsStyle { didSet { defaults.set(eventDots.rawValue, forKey: Key.eventDots) } }
    var weekStart: WeekStart { didSet { defaults.set(weekStart.rawValue, forKey: Key.weekStart) } }
    var showMonthGrid: Bool { didSet { defaults.set(showMonthGrid, forKey: Key.showMonthGrid) } }

    // MARK: Layout

    var textSize: TextSize { didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) } }
    var calendarDensity: Density { didSet { defaults.set(calendarDensity.rawValue, forKey: Key.calendarDensity) } }
    var eventDensity: Density { didSet { defaults.set(eventDensity.rawValue, forKey: Key.eventDensity) } }
    /// How many days ahead the agenda list looks.
    var agendaDayCount: Int { didSet { defaults.set(agendaDayCount, forKey: Key.agendaDayCount) } }
    var hideEmptyDays: Bool { didSet { defaults.set(hideEmptyDays, forKey: Key.hideEmptyDays) } }
    var hideAllDayEvents: Bool { didSet { defaults.set(hideAllDayEvents, forKey: Key.hideAllDayEvents) } }
    var hidePastEvents: Bool { didSet { defaults.set(hidePastEvents, forKey: Key.hidePastEvents) } }

    // MARK: Calendars

    /// Calendar for new events; `nil` uses the system default.
    var defaultCalendarID: String? { didSet { defaults.set(defaultCalendarID, forKey: Key.defaultCalendarID) } }
    var ignoredTitleKeywords: String { didSet { defaults.set(ignoredTitleKeywords, forKey: Key.ignoredTitleKeywords) } }
    var mapsProvider: MapsProvider { didSet { defaults.set(mapsProvider.rawValue, forKey: Key.mapsProvider) } }
    var hiddenCalendarIDs: Set<String> { didSet { defaults.set(Array(hiddenCalendarIDs), forKey: Key.hiddenCalendarIDs) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.globalShortcutsEnabled: true,
            Key.checkForUpdates: true,
            Key.nextEventLeadMinutes: 30,
            Key.showYearProgress: true,
            Key.highlightToday: true,
            Key.showMonthGrid: true,
            Key.agendaDayCount: 14,
            Key.hideEmptyDays: true,
        ])

        keepCalendarOnTop = defaults.bool(forKey: Key.keepCalendarOnTop)
        appearance = Self.value(defaults, Key.appearance, default: .system)
        globalShortcutsEnabled = defaults.bool(forKey: Key.globalShortcutsEnabled)
        customVideoServices = Self.decoded(defaults, Key.customVideoServices) ?? []
        checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)

        menuBarFormat = Self.decoded(defaults, Key.menuBarFormat) ?? MenuBarFormat()
        nextEventLeadMinutes = defaults.integer(forKey: Key.nextEventLeadMinutes)

        showDaySummary = defaults.bool(forKey: Key.showDaySummary)
        showFreeTime = defaults.bool(forKey: Key.showFreeTime)
        showYearProgress = defaults.bool(forKey: Key.showYearProgress)
        showDayProgress = defaults.bool(forKey: Key.showDayProgress)
        showWeekNumbers = defaults.bool(forKey: Key.showWeekNumbers)
        highlightToday = defaults.bool(forKey: Key.highlightToday)
        dimWeekends = defaults.bool(forKey: Key.dimWeekends)
        eventDots = Self.value(defaults, Key.eventDots, default: .colors)
        let localeWeekStart: WeekStart = Calendar.current.firstWeekday == 2 ? .monday : .sunday
        weekStart = (defaults.object(forKey: Key.weekStart) as? Int).flatMap(WeekStart.init(rawValue:)) ?? localeWeekStart
        showMonthGrid = defaults.bool(forKey: Key.showMonthGrid)

        textSize = Self.value(defaults, Key.textSize, default: .standard)
        calendarDensity = Self.value(defaults, Key.calendarDensity, default: .compact)
        eventDensity = Self.value(defaults, Key.eventDensity, default: .compact)
        agendaDayCount = min(max(defaults.integer(forKey: Key.agendaDayCount), 1), Self.maxAgendaDayCount)
        hideEmptyDays = defaults.bool(forKey: Key.hideEmptyDays)
        hideAllDayEvents = defaults.bool(forKey: Key.hideAllDayEvents)
        hidePastEvents = defaults.bool(forKey: Key.hidePastEvents)

        defaultCalendarID = defaults.string(forKey: Key.defaultCalendarID)
        ignoredTitleKeywords = defaults.string(forKey: Key.ignoredTitleKeywords) ?? ""
        mapsProvider = Self.value(defaults, Key.mapsProvider, default: .apple)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? [])
    }

    var customMeetingHosts: [String] {
        customVideoServices.map(\.host)
    }

    func isCalendarVisible(_ id: String) -> Bool {
        !hiddenCalendarIDs.contains(id)
    }

    func setCalendar(_ id: String, visible: Bool) {
        if visible {
            hiddenCalendarIDs.remove(id)
        } else {
            hiddenCalendarIDs.insert(id)
        }
    }

    /// The "All" button in Settings › Calendars.
    func showAllCalendars() {
        hiddenCalendarIDs = []
    }

    /// The "None" button in Settings › Calendars.
    func hideAllCalendars(_ ids: [String]) {
        hiddenCalendarIDs = Set(ids)
    }

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func decoded<T: Decodable>(_ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func value<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, default fallback: T) -> T
    where T.RawValue == String {
        defaults.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
    }
}
