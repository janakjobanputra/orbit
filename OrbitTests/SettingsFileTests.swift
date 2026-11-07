import KeyboardShortcuts
import XCTest
@testable import Orbit

@MainActor
final class SettingsFileTests: XCTestCase {

    private func preferences() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "OrbitSettingsFile-\(UUID().uuidString)")!)
    }

    private let calendars = [
        StateFixture.calendarInfo("id-work", source: "Google"),
        StateFixture.calendarInfo("id-home", source: "iCloud"),
    ]

    /// Changes every setting away from its default, so a missed one shows up in the round trip.
    private func customized(_ p: Preferences) {
        p.keepCalendarOnTop = true
        p.appearance = .dark
        p.globalShortcutsEnabled = false
        p.checkForUpdates = false
        p.shareUsageStats = true
        p.sendCrashReports = false
        p.customVideoServices = [CustomVideoService(name: "Acme", host: "meet.acme.com")]
        p.menuBarFormat.preset = .custom
        p.menuBarFormat.customTokens = [.weekNumber, .time]
        p.menuBarFormat.timePattern = "HH:mm"
        p.menuBarFormat.separator = .dash
        p.nextEventLeadMinutes = 45
        p.showDaySummary = true
        p.showFreeTime = true
        p.showYearProgress = false
        p.showDayProgress = true
        p.showWeekNumbers = true
        p.highlightToday = false
        p.dimWeekends = true
        p.eventDots = .off
        p.weekStart = .monday
        p.showMonthGrid = false
        p.textSize = TextSize.allCases.last!
        p.calendarDensity = .airy
        p.eventDensity = .cozy
        p.eventsView = .agenda
        p.agendaDayCount = 7
        p.hideEmptyDays = false
        p.hideAllDayEvents = true
        p.hidePastEvents = true
        p.showDeclinedEvents = true
        p.defaultCalendarID = "id-home"
        p.setCalendar("id-work", visible: false)
        p.ignoredTitleKeywords = "daycare, gym"
        p.mapsProvider = MapsProvider.allCases.last!
    }

    func testEverySettingSurvivesARoundTripThroughTheFile() throws {
        let source = preferences()
        customized(source)
        let data = try SettingsFile(settings: source.settingsValues(calendars: calendars)).encoded()

        let target = preferences()
        let result = target.apply(try SettingsFile.read(data).settings, calendars: calendars)

        XCTAssertEqual(result, SettingsImportResult())
        XCTAssertEqual(target.settingsValues(calendars: calendars), source.settingsValues(calendars: calendars))
        XCTAssertEqual(target.hiddenCalendarIDs, ["id-work"])
        XCTAssertEqual(target.defaultCalendarID, "id-home")
        XCTAssertEqual(target.customVideoServices.map(\.host), ["meet.acme.com"])
    }

    func testTheTestAboveCoversEverySetting() {
        // Every setting differs from a fresh install, or the round trip would pass by accident.
        let fresh = preferences()
        let changed = preferences()
        customized(changed)
        let a = Mirror(reflecting: fresh.settingsValues(calendars: calendars)).children
        let b = Mirror(reflecting: changed.settingsValues(calendars: calendars)).children
        for (x, y) in zip(a, b) where !["launchAtLogin", "shortcuts"].contains(x.label) {
            XCTAssertNotEqual(String(describing: x.value), String(describing: y.value), "\(x.label ?? "?") isn't exercised")
        }
    }

    func testCalendarsAreMatchedByNameOnAnotherMac() {
        let source = preferences()
        source.setCalendar("id-work", visible: false)
        source.defaultCalendarID = "id-home"
        let values = source.settingsValues(calendars: calendars)

        let otherMac = [
            CalendarInfo(id: "other-work", title: "Id-Work", sourceTitle: "Google", color: .fallback, isWritable: true),
            CalendarInfo(id: "other-home", title: "Id-Home", sourceTitle: "iCloud", color: .fallback, isWritable: true),
        ]
        let target = preferences()
        XCTAssertEqual(target.apply(values, calendars: otherMac), SettingsImportResult())
        XCTAssertEqual(target.hiddenCalendarIDs, ["other-work"])
        XCTAssertEqual(target.defaultCalendarID, "other-home")
    }

    func testCalendarsNotOnThisMacAreReported() {
        let source = preferences()
        source.setCalendar("id-work", visible: false)
        let target = preferences()
        let result = target.apply(source.settingsValues(calendars: calendars), calendars: [])
        XCTAssertEqual(result.unmatchedCalendars, ["Id-Work"])
        XCTAssertEqual(target.hiddenCalendarIDs, [])
    }

    func testAFileOnlyChangesWhatItMentions() throws {
        let target = preferences()
        customized(target)
        let json = #"{"app": "Orbit", "settings": {"showWeekNumbers": false, "eventsView": "day"}}"#
        target.apply(try SettingsFile.read(Data(json.utf8)).settings, calendars: calendars)
        XCTAssertFalse(target.showWeekNumbers)
        XCTAssertEqual(target.eventsView, .day)
        XCTAssertEqual(target.nextEventLeadMinutes, 45, "Not in the file")
        XCTAssertEqual(target.hiddenCalendarIDs, ["id-work"], "Not in the file")
    }

    func testBadValuesAreSkippedOrBroughtInRange() throws {
        let target = preferences()
        let json = #"{"app": "Orbit", "settings": {"appearance": "neon", "nextEventLeadMinutes": 9000, "agendaDayCount": 6, "weekStart": 42, "futureSetting": true}}"#
        target.apply(try SettingsFile.read(Data(json.utf8)).settings, calendars: calendars)
        XCTAssertEqual(target.appearance, .system)
        XCTAssertEqual(target.nextEventLeadMinutes, 120)
        XCTAssertTrue(Preferences.agendaDayOptions.contains(target.agendaDayCount))
        XCTAssertEqual(target.agendaDayCount, 5)
        XCTAssertNotEqual(target.weekStart.rawValue, 42)
    }

    func testFilesThatArentOrbitSettingsAreRefused() {
        func error(_ text: String) -> SettingsFile.ReadError? {
            XCTAssertThrowsError(try SettingsFile.read(Data(text.utf8)))
            do { _ = try SettingsFile.read(Data(text.utf8)); return nil } catch { return error as? SettingsFile.ReadError }
        }
        XCTAssertEqual(error("not json"), .notJSON)
        XCTAssertEqual(error(#"{"name": "some other app"}"#), .notOrbit)
        XCTAssertEqual(error(#"{"app": "Orbit", "format": 99, "settings": {}}"#), .newerFormat)
        XCTAssertEqual(error(#"{"app": "Orbit", "settings": {"showWeekNumbers": "maybe"}}"#), .notJSON)
    }

    func testShortcutsAndLoginItemAreInTheFile() async throws {
        let (state, _, _) = await StateFixture.make()
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        let file = state.settingsFile(launchAtLogin: true, shortcuts: .init(toggleCalendar: shortcut, joinNextMeeting: nil), appVersion: "1.1.5")
        let read = try SettingsFile.read(file.encoded())
        XCTAssertEqual(read.settings.shortcuts?.toggleCalendar, shortcut)
        XCTAssertNil(read.settings.shortcuts?.joinNextMeeting)
        XCTAssertEqual(read.settings.launchAtLogin, true)
        XCTAssertEqual(read.exportedFromVersion, "1.1.5")
    }

    func testImportingRedrawsFromTheNewSettings() async throws {
        let (state, _, _) = await StateFixture.make { store, _ in
            store.calendarList = [StateFixture.calendarInfo("work")]
            store.add(TestSupport.event("Standup", start: TestSupport.date(2026, 10, 31, 10), minutes: 15), link: "https://meet.acme.com/x")
        }
        XCTAssertNil(state.agendaDays.flatMap(\.events).first?.meetingURL)
        var values = SettingsFile.Values()
        values.customVideoServices = [.init(name: "Acme", host: "meet.acme.com")]
        _ = state.importSettings(SettingsFile(settings: values))
        XCTAssertNotNil(state.agendaDays.flatMap(\.events).first?.meetingURL)
    }
}
