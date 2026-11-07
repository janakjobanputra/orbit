import Foundation
import KeyboardShortcuts

/// Everything in Settings, as a JSON file you can keep or move to another Mac.
/// Every setting is optional, so a file from another version, or one edited by hand down to a few lines, only
/// changes what it mentions. Settings are stored by name and options as plain words, so the file stays readable.
struct SettingsFile: Codable, Equatable {

    static let currentFormat = 1

    /// A calendar named by its account as well as its ID, because IDs differ from one Mac to the next.
    struct CalendarReference: Codable, Equatable {
        var id: String
        var title: String
        var source: String
    }

    struct Shortcuts: Codable, Equatable {
        var toggleCalendar: KeyboardShortcuts.Shortcut?
        var joinNextMeeting: KeyboardShortcuts.Shortcut?
    }

    struct VideoService: Codable, Equatable {
        var name: String
        var host: String
    }

    struct Values: Codable, Equatable {
        // General
        var launchAtLogin: Bool?
        var keepCalendarOnTop: Bool?
        var appearance: String?
        var globalShortcutsEnabled: Bool?
        var shortcuts: Shortcuts?
        var checkForUpdates: Bool?
        var shareUsageStats: Bool?
        var sendCrashReports: Bool?
        var customVideoServices: [VideoService]?
        // Menu bar
        var menuBarFormat: MenuBarFormat?
        var nextEventLeadMinutes: Int?
        // Calendar display
        var showDaySummary: Bool?
        var showFreeTime: Bool?
        var showYearProgress: Bool?
        var showDayProgress: Bool?
        var showWeekNumbers: Bool?
        var highlightToday: Bool?
        var dimWeekends: Bool?
        var eventDots: String?
        var weekStart: Int?
        var showMonthGrid: Bool?
        // Layout
        var textSize: String?
        var calendarDensity: String?
        var eventDensity: String?
        var eventsView: String?
        var agendaDayCount: Int?
        var hideEmptyDays: Bool?
        var hideAllDayEvents: Bool?
        var hidePastEvents: Bool?
        var showDeclinedEvents: Bool?
        // Calendars
        var defaultCalendar: CalendarReference?
        var hiddenCalendars: [CalendarReference]?
        var ignoredTitleKeywords: String?
        var mapsProvider: String?
    }

    var app = "Orbit"
    var format: Int? = currentFormat
    var exportedFromVersion: String?
    var settings: Values

    enum ReadError: LocalizedError, Equatable {
        case notJSON
        case notOrbit
        case newerFormat

        var errorDescription: String? {
            switch self {
            case .notJSON: "This file isn't a settings file Orbit can read."
            case .notOrbit: "This file doesn't contain Orbit settings."
            case .newerFormat: "This file came from a newer version of Orbit. Update Orbit, then import it again."
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func read(_ data: Data) throws -> SettingsFile {
        // The header on its own first, so a file from a newer Orbit gets the right message even if its settings changed shape.
        struct Header: Decodable {
            var app: String?
            var format: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw ReadError.notJSON }
        guard header.app == "Orbit" else { throw ReadError.notOrbit }
        guard (header.format ?? currentFormat) <= currentFormat else { throw ReadError.newerFormat }
        guard let file = try? JSONDecoder().decode(SettingsFile.self, from: data) else { throw ReadError.notJSON }
        return file
    }
}

/// What importing did, for the message afterwards.
struct SettingsImportResult: Equatable {
    /// Calendars the file mentions that aren't on this Mac, so their setting couldn't be applied.
    var unmatchedCalendars: [String] = []
}

extension Preferences {

    /// Your settings as they stand. `calendars` are the ones on this Mac, to name the hidden ones.
    func settingsValues(calendars: [CalendarInfo]) -> SettingsFile.Values {
        func reference(_ id: String) -> SettingsFile.CalendarReference? {
            calendars.first { $0.id == id }.map { .init(id: $0.id, title: $0.title, source: $0.sourceTitle) }
        }
        return SettingsFile.Values(
            keepCalendarOnTop: keepCalendarOnTop,
            appearance: appearance.rawValue,
            globalShortcutsEnabled: globalShortcutsEnabled,
            checkForUpdates: checkForUpdates,
            shareUsageStats: shareUsageStats,
            sendCrashReports: sendCrashReports,
            customVideoServices: customVideoServices.map { .init(name: $0.name, host: $0.host) },
            menuBarFormat: menuBarFormat,
            nextEventLeadMinutes: nextEventLeadMinutes,
            showDaySummary: showDaySummary,
            showFreeTime: showFreeTime,
            showYearProgress: showYearProgress,
            showDayProgress: showDayProgress,
            showWeekNumbers: showWeekNumbers,
            highlightToday: highlightToday,
            dimWeekends: dimWeekends,
            eventDots: eventDots.rawValue,
            weekStart: weekStart.rawValue,
            showMonthGrid: showMonthGrid,
            textSize: textSize.rawValue,
            calendarDensity: calendarDensity.rawValue,
            eventDensity: eventDensity.rawValue,
            eventsView: eventsView.rawValue,
            agendaDayCount: agendaDayCount,
            hideEmptyDays: hideEmptyDays,
            hideAllDayEvents: hideAllDayEvents,
            hidePastEvents: hidePastEvents,
            showDeclinedEvents: showDeclinedEvents,
            defaultCalendar: defaultCalendarID.flatMap(reference),
            hiddenCalendars: hiddenCalendarIDs.sorted().compactMap(reference),
            ignoredTitleKeywords: ignoredTitleKeywords,
            mapsProvider: mapsProvider.rawValue
        )
    }

    /// Changes what the file mentions and leaves the rest alone. Options this version doesn't know are skipped.
    @discardableResult
    func apply(_ values: SettingsFile.Values, calendars: [CalendarInfo]) -> SettingsImportResult {
        var result = SettingsImportResult()

        func set<T>(_ value: T?, _ assign: (T) -> Void) {
            if let value { assign(value) }
        }
        func option<T: RawRepresentable>(_ raw: String?, _ assign: (T) -> Void) where T.RawValue == String {
            if let value = raw.flatMap(T.init(rawValue:)) { assign(value) }
        }
        /// The same calendar on this Mac: by ID on the Mac it came from, otherwise by account and name.
        func match(_ reference: SettingsFile.CalendarReference) -> CalendarInfo? {
            calendars.first { $0.id == reference.id }
                ?? calendars.first { $0.title == reference.title && $0.sourceTitle == reference.source }
        }

        set(values.keepCalendarOnTop) { keepCalendarOnTop = $0 }
        option(values.appearance) { (value: AppearanceMode) in appearance = value }
        set(values.globalShortcutsEnabled) { globalShortcutsEnabled = $0 }
        set(values.checkForUpdates) { checkForUpdates = $0 }
        set(values.shareUsageStats) { shareUsageStats = $0 }
        set(values.sendCrashReports) { sendCrashReports = $0 }
        set(values.customVideoServices) { services in
            customVideoServices = services.compactMap { service in
                CustomVideoService.normalizedHost(from: service.host).map { CustomVideoService(name: service.name, host: $0) }
            }
        }

        set(values.menuBarFormat) { menuBarFormat = $0 }
        set(values.nextEventLeadMinutes) { nextEventLeadMinutes = min(max($0, 5), 120) }

        set(values.showDaySummary) { showDaySummary = $0 }
        set(values.showFreeTime) { showFreeTime = $0 }
        set(values.showYearProgress) { showYearProgress = $0 }
        set(values.showDayProgress) { showDayProgress = $0 }
        set(values.showWeekNumbers) { showWeekNumbers = $0 }
        set(values.highlightToday) { highlightToday = $0 }
        set(values.dimWeekends) { dimWeekends = $0 }
        option(values.eventDots) { (value: EventDotsStyle) in eventDots = value }
        set(values.weekStart.flatMap(WeekStart.init(rawValue:))) { weekStart = $0 }
        set(values.showMonthGrid) { showMonthGrid = $0 }

        option(values.textSize) { (value: TextSize) in textSize = value }
        option(values.calendarDensity) { (value: Density) in calendarDensity = value }
        option(values.eventDensity) { (value: Density) in eventDensity = value }
        option(values.eventsView) { (value: EventsView) in eventsView = value }
        // The nearest length the Agenda days menu offers, so the menu always has something selected.
        set(values.agendaDayCount) { count in
            agendaDayCount = Preferences.agendaDayOptions.min { abs($0 - count) < abs($1 - count) } ?? agendaDayCount
        }
        set(values.hideEmptyDays) { hideEmptyDays = $0 }
        set(values.hideAllDayEvents) { hideAllDayEvents = $0 }
        set(values.hidePastEvents) { hidePastEvents = $0 }
        set(values.showDeclinedEvents) { showDeclinedEvents = $0 }

        set(values.defaultCalendar) { reference in
            if let calendar = match(reference) {
                defaultCalendarID = calendar.id
            } else {
                result.unmatchedCalendars.append(reference.title)
            }
        }
        set(values.hiddenCalendars) { references in
            hiddenCalendarIDs = Set(references.compactMap { reference in
                let calendar = match(reference)
                if calendar == nil { result.unmatchedCalendars.append(reference.title) }
                return calendar?.id
            })
        }
        set(values.ignoredTitleKeywords) { ignoredTitleKeywords = $0 }
        option(values.mapsProvider) { (value: MapsProvider) in mapsProvider = value }

        return result
    }
}

extension AppState {

    /// The file for your current settings. Login item and shortcuts are passed in because they live outside Preferences.
    func settingsFile(launchAtLogin: Bool?, shortcuts: SettingsFile.Shortcuts?, appVersion: String?) -> SettingsFile {
        var values = preferences.settingsValues(calendars: calendars)
        values.launchAtLogin = launchAtLogin
        values.shortcuts = shortcuts
        return SettingsFile(exportedFromVersion: appVersion, settings: values)
    }

    /// Applies a file and redraws everything from it, as custom video services change which events get a Join button.
    func importSettings(_ file: SettingsFile) -> SettingsImportResult {
        let result = preferences.apply(file.settings, calendars: calendars)
        reload()
        return result
    }
}
