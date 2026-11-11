import AppKit
import SwiftUI
import XCTest
@testable import Orbit

/// Renders the real popover for each option of the settings that only change how it looks,
/// checks every option draws something different, and attaches the images to the test results.
@MainActor
final class PopoverRenderingTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 31) -> Date {
        TestSupport.date(2026, 10, day, hour, minute)
    }

    private func makeState() async -> AppState {
        await StateFixture.make { store, preferences in
            let blue = EventColor(red: 0.2, green: 0.5, blue: 1)
            let pink = EventColor(red: 0.9, green: 0.3, blue: 0.7)
            let green = EventColor(red: 0.2, green: 0.8, blue: 0.4)
            @MainActor func add(_ title: String, _ start: Date, _ end: Date, _ color: EventColor, allDay: Bool = false) {
                store.add(CalendarEvent(
                    id: title, title: title, start: start, end: end, isAllDay: allDay,
                    calendarID: "work", color: color, location: nil, meetingURL: nil
                ))
            }
            add("Halloween", TestSupport.date(2026, 10, 31), TestSupport.date(2026, 11, 1), pink, allDay: true)
            add("Woodworking", at(13), at(15), blue)
            add("Standup", at(10), at(10, 15), green)
            add("Dentist", at(9, day: 27), at(10, day: 27), blue)
            add("Lunch", at(12, day: 27), at(13, day: 27), pink)
            add("Run", at(7, day: 24), at(8, day: 24), green)
            preferences.weekStart = .sunday
        }.state
    }

    /// Lays the popover out at its natural size in an offscreen window and draws it.
    private func render(_ state: AppState, scheme: ColorScheme = .light) -> NSBitmapImageRep {
        snapshot(host(state, scheme: scheme))
    }

    private func host(_ state: AppState, scheme: ColorScheme = .light) -> NSView {
        let root = PopoverView(openSettings: {})
            .environment(state)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
            // The fixture's dates are UTC, so draw them in UTC rather than this Mac's time zone.
            .environment(\.timeZone, TestSupport.utc)
            .environment(\.calendar, state.calendar)
        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        return host
    }

    /// Draws a view that may already be on screen, after letting SwiftUI catch up with any state change.
    private func snapshot(_ host: NSView) -> NSBitmapImageRep {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func attach(_ rep: NSBitmapImageRep, _ name: String) {
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

    /// Renders once per option and asserts no two options look the same.
    private func assertEachOptionDiffers<T>(
        _ name: String,
        _ options: [T],
        label: (T) -> String = { "\($0)" },
        apply: (AppState, T) -> Void
    ) async {
        let state = await makeState()
        var images: [(String, Data)] = []
        for option in options {
            apply(state, option)
            let rep = render(state)
            attach(rep, "\(name) = \(label(option))")
            images.append((label(option), png(rep)))
        }
        for i in images.indices {
            for j in images.indices where j > i {
                XCTAssertNotEqual(images[i].1, images[j].1, "\(name): \(images[i].0) and \(images[j].0) look identical")
            }
        }
    }

    func testRendersSomething() async {
        let rep = render(await makeState())
        attach(rep, "Baseline")
        XCTAssertGreaterThan(rep.pixelsHigh, 300)
        XCTAssertEqual(rep.size.width, 300, accuracy: 0.5)
    }

    func testDaySummary() async {
        await assertEachOptionDiffers("Day summary", [false, true]) { $0.preferences.showDaySummary = $1 }
    }

    func testShowFreeTime() async {
        await assertEachOptionDiffers("Show free time", [false, true]) { $0.preferences.showFreeTime = $1 }
    }

    func testYearProgress() async {
        await assertEachOptionDiffers("Year progress", [false, true]) { $0.preferences.showYearProgress = $1 }
    }

    func testDayProgress() async {
        await assertEachOptionDiffers("Day progress", [false, true]) { $0.preferences.showDayProgress = $1 }
    }

    func testWeekNumbers() async {
        await assertEachOptionDiffers("Week numbers", [false, true]) { $0.preferences.showWeekNumbers = $1 }
    }

    func testHighlightToday() async {
        await assertEachOptionDiffers("Highlight today", [false, true]) { $0.preferences.highlightToday = $1 }
    }

    func testDimWeekends() async {
        await assertEachOptionDiffers("Dim weekends", [false, true]) { $0.preferences.dimWeekends = $1 }
    }

    func testEventDots() async {
        await assertEachOptionDiffers("Event dots", EventDotsStyle.allCases) { $0.preferences.eventDots = $1 }
    }

    func testWeekStart() async {
        await assertEachOptionDiffers("Week starts on", WeekStart.allCases) { $0.preferences.weekStart = $1 }
    }

    func testCalendarShows() async {
        await assertEachOptionDiffers("Calendar shows", CalendarSpan.allCases) { $0.preferences.calendarSpan = $1 }
    }

    func testShowMonth() async {
        await assertEachOptionDiffers("Show month", [true, false]) { $0.preferences.showMonthGrid = $1 }
    }

    func testTextSize() async {
        await assertEachOptionDiffers("Text size", TextSize.allCases) { $0.preferences.textSize = $1 }
        let state = await makeState()
        for size in TextSize.allCases {
            state.preferences.textSize = size
            XCTAssertEqual(render(state).size.width, 300 * size.scale, accuracy: 0.5, "Popover width at \(size)")
        }
    }

    func testCalendarDensity() async {
        await assertEachOptionDiffers("Calendar density", Density.allCases) { $0.preferences.calendarDensity = $1 }
    }

    func testEventDensity() async {
        await assertEachOptionDiffers("Event density", Density.allCases) { $0.preferences.eventDensity = $1 }
    }

    func testHideAllDayEvents() async {
        await assertEachOptionDiffers("Hide all-day events", [false, true]) { $0.preferences.hideAllDayEvents = $1 }
    }

    func testHidePastEvents() async {
        await assertEachOptionDiffers("Hide past events", [false, true]) { state, hide in
            state.preferences.hidePastEvents = hide
            state.show(date: TestSupport.date(2026, 10, 27, 12))
        }
    }

    /// The year bar at the start, a sliver in, the middle, near the end and the last minute of the year.
    func testYearProgressThroughTheYear() async {
        let moments = [
            ("1 Jan 00:00", TestSupport.date(2026, 1, 1)),
            ("3 Jan", TestSupport.date(2026, 1, 3, 12)),
            ("2 Jul", TestSupport.date(2026, 7, 2, 12)),
            ("31 Oct", TestSupport.date(2026, 10, 31, 9, 47)),
            ("30 Dec", TestSupport.date(2026, 12, 30, 12)),
            ("31 Dec 23:59", TestSupport.date(2026, 12, 31, 23, 59)),
        ]
        var images: [Data] = []
        for (name, date) in moments {
            let state = await StateFixture.make(at: date) { _, preferences in
                preferences.showYearProgress = true
                preferences.showDayProgress = true
            }.state
            let rep = render(state)
            attach(rep, "Year progress at \(name)")
            images.append(png(rep))
        }
        XCTAssertEqual(Set(images).count, moments.count)
    }

    /// Flipping to a month must draw it exactly as opening straight onto it does: no styling left over from
    /// the month before, for days that appear in both grids.
    func testFlippingMonthsMatchesAFreshRender() async {
        let november = TestSupport.date(2026, 11, 1, 20, 15)
        let flipped = await StateFixture.make(at: november).state
        let view = host(flipped)
        _ = snapshot(view)
        flipped.showPage(offset: 1)
        let afterFlip = snapshot(view)

        let fresh = await StateFixture.make(at: november).state
        fresh.displayedMonth = TestSupport.date(2026, 12, 1)
        let direct = render(fresh)

        attach(afterFlip, "December after flipping from November")
        attach(direct, "December drawn directly")
        XCTAssertEqual(png(afterFlip), png(direct))
    }

    /// The event happening now gets the tinted card with its links; the one after stays compact.
    func testHighlightedEventCard() async {
        let state = await StateFixture.make(at: at(13, 12)) { store, _ in
            var call = CalendarEvent(
                id: "call", title: "Design review", start: at(13), end: at(13, 30), isAllDay: false,
                calendarID: "work", color: EventColor(red: 0.2, green: 0.5, blue: 1), location: "Studio", meetingURL: nil
            )
            call.calendarItemID = "call"
            store.add(call, link: "https://meet.google.com/abc-defg-hij https://docs.google.com/document/d/1")
            store.add(TestSupport.event("Dinner", start: at(19), minutes: 60))
        }.state
        state.preferences.showMonthGrid = false
        let rep = render(state)
        attach(rep, "Highlighted event")
        XCTAssertGreaterThan(rep.pixelsHigh, 100)
    }

    /// The Day view: all-day events on top, overlapping meetings side by side, and a line at the current time.
    func testDayView() async {
        let state = await StateFixture.make(at: at(10, 40)) { store, preferences in
            let blue = EventColor(red: 0.22, green: 0.52, blue: 0.98), green = EventColor(red: 0.2, green: 0.7, blue: 0.42)
            @MainActor func add(_ title: String, _ start: Date, _ end: Date, _ color: EventColor, allDay: Bool = false) {
                store.add(CalendarEvent(
                    id: title, title: title, start: start, end: end, isAllDay: allDay,
                    calendarID: "work", color: color, location: nil, meetingURL: nil
                ))
            }
            add("Halloween", TestSupport.date(2026, 10, 31), TestSupport.date(2026, 11, 1), EventColor(red: 0.9, green: 0.3, blue: 0.7), allDay: true)
            add("Standup", at(9), at(9, 30), blue)
            add("Design review", at(10, 15), at(11), blue)
            add("Coffee with Priya", at(10, 30), at(11, 15), green)
            add("Focus time", at(11, 30), at(13), blue)
            preferences.eventsView = .day
        }.state
        state.preferences.showMonthGrid = false
        XCTAssertEqual(state.dayTimeline.blocks.count, 4)
        for scheme in [ColorScheme.light, .dark] {
            let rep = render(state, scheme: scheme)
            attach(rep, "Day view (\(scheme == .light ? "light" : "dark"))")
            XCTAssertGreaterThan(rep.pixelsHigh, 300)
        }
    }

    /// Invitations you haven't accepted are marked in both views; declined ones only show when turned on.
    func testAttendanceMarks() async {
        let blue = EventColor(red: 0.22, green: 0.52, blue: 0.98), green = EventColor(red: 0.2, green: 0.7, blue: 0.42)
        func invite(_ title: String, _ start: Date, _ end: Date, _ color: EventColor, _ response: Guest.Response?) -> CalendarEvent {
            var event = CalendarEvent(id: title, title: title, start: start, end: end, isAllDay: false,
                                      calendarID: "work", color: color, location: nil, meetingURL: nil)
            if let response {
                event.guests = [Guest(name: "You", response: response, isYou: true), Guest(name: "Sam", response: .accepted, isOrganizer: true)]
            }
            return event
        }
        let state = await StateFixture.make(at: at(9, 40)) { store, preferences in
            store.add(invite("Standup", at(10), at(10, 30), blue, .accepted))
            store.add(invite("Vendor pitch", at(11), at(12), blue, .pending))
            store.add(invite("Offsite planning", at(12, 30), at(13, 30), green, .tentative))
            store.add(invite("Budget review", at(14), at(15), blue, .declined))
            store.add(invite("Focus time", at(15, 30), at(16, 30), green, nil))
            preferences.showDeclinedEvents = true
        }.state
        state.preferences.showMonthGrid = false
        for view in [EventsView.agenda, .day] {
            state.preferences.eventsView = view
            state.preferences.eventDensity = .cozy
            for scheme in [ColorScheme.light, .dark] {
                attach(render(state, scheme: scheme), "Attendance \(view.rawValue) (\(scheme == .light ? "light" : "dark"))")
            }
        }
    }

    /// Late in the day, today says there's nothing left instead of ending on a finished event.
    func testNothingLeftToday() async {
        let state = await StateFixture.make(at: at(21)) { store, _ in
            store.add(CalendarEvent(
                id: "halloween", title: "Halloween", start: TestSupport.date(2026, 10, 31), end: TestSupport.date(2026, 11, 1),
                isAllDay: true, calendarID: "work", color: EventColor(red: 0.9, green: 0.3, blue: 0.7), location: nil, meetingURL: nil
            ))
            store.add(TestSupport.event("Movie", start: at(19), minutes: 90))
            store.add(TestSupport.event("Brunch", start: at(11, day: 1), minutes: 60))
        }.state
        state.preferences.showMonthGrid = false
        XCTAssertTrue(state.agendaDays[0].hasNothingLeft(now: state.now))
        for scheme in [ColorScheme.light, .dark] {
            attach(render(state, scheme: scheme), "Nothing left today (\(scheme == .light ? "light" : "dark"))")
        }
    }

    /// A newer version adds an Update row at the bottom of the calendar.
    func testUpdateBanner() async {
        let plain = render(await makeState())
        let state = await StateFixture.make(at: at(13, 12), availableVersion: "1.1.6").state
        for scheme in [ColorScheme.light, .dark] {
            let rep = render(state, scheme: scheme)
            attach(rep, "Update banner (\(scheme == .light ? "light" : "dark"))")
            XCTAssertGreaterThan(rep.pixelsHigh, plain.pixelsHigh - 200)
        }
    }

    func testEventDetailView() async {
        let state = await StateFixture.make(at: at(13, 12)).state
        var event = CalendarEvent(
            id: "call", title: "Design review", start: at(13), end: at(13, 30), isAllDay: false,
            calendarID: "work", color: EventColor(red: 0.2, green: 0.5, blue: 1), location: "Studio, 12 Main St",
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        event.notes = "Bring sketches. Agenda at https://docs.google.com/document/d/1"
        event.links = [URL(string: "https://docs.google.com/document/d/1")!]
        event.guests = [
            Guest(name: "Ana Ruiz", response: .accepted, isOrganizer: true),
            Guest(name: "Ben Ito", response: .accepted),
            Guest(name: "Cy Moss", response: .tentative),
        ]
        event.calendarItemID = "call"
        for scheme in [ColorScheme.light, .dark] {
            let root = EventDetailView(event: event)
                .environment(state)
                .background(scheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, scheme)
                .environment(\.timeZone, TestSupport.utc)
                .environment(\.calendar, state.calendar)
            let host = NSHostingView(rootView: root)
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            let rep = snapshot(host)
            attach(rep, "Event detail (\(scheme == .dark ? "dark" : "light"))")
            XCTAssertEqual(rep.size.width, 300, accuracy: 0.5)
        }
    }

    /// Scrolls the agenda part way into a day: its title and all-day events stay pinned at the top.
    func testAllDayEventsStayPinnedWhileScrolling() async {
        let state = await StateFixture.make(at: at(7)) { store, _ in
            for day in 31...31 {
                store.add(TestSupport.event("Halloween", start: TestSupport.date(2026, 10, day), minutes: 24 * 60, isAllDay: true))
            }
            store.add(TestSupport.event("Day of the Dead", start: TestSupport.date(2026, 11, 1), minutes: 24 * 60, isAllDay: true))
            for (index, hour) in [8, 9, 10, 11, 12, 13, 14, 15, 16].enumerated() {
                store.add(TestSupport.event("Block \(index + 1)", start: at(hour), minutes: 45))
            }
            store.add(TestSupport.event("Brunch", start: TestSupport.date(2026, 11, 1, 11), minutes: 60))
        }.state
        state.preferences.showMonthGrid = false
        state.preferences.showYearProgress = false
        let view = host(state)
        let top = snapshot(view)
        attach(top, "Agenda at the top")

        let scrollView = try? XCTUnwrap(allSubviews(of: view).compactMap { $0 as? NSScrollView }.first)
        let images = [180.0, 420.0].map { offset -> NSBitmapImageRep in
            scrollView?.contentView.scroll(to: NSPoint(x: 0, y: offset))
            if let scrollView { scrollView.reflectScrolledClipView(scrollView.contentView) }
            let rep = snapshot(view)
            attach(rep, "Agenda scrolled \(Int(offset))pt")
            return rep
        }
        XCTAssertNotNil(scrollView)
        XCTAssertNotEqual(png(top), png(images[0]))
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    /// The images used in the README and on the website: a realistic afternoon, light and dark, plus an event's details.
    func testMarketingScreenshots() async {
        let blue = EventColor(red: 0.22, green: 0.52, blue: 0.98)
        let pink = EventColor(red: 0.85, green: 0.33, blue: 0.62)
        let green = EventColor(red: 0.20, green: 0.70, blue: 0.42)
        let orange = EventColor(red: 0.96, green: 0.56, blue: 0.20)
        func event(_ title: String, _ start: Date, _ end: Date, _ color: EventColor, allDay: Bool = false, location: String? = nil) -> CalendarEvent {
            var event = CalendarEvent(
                id: title, title: title, start: start, end: end, isAllDay: allDay,
                calendarID: "work", color: color, location: location, meetingURL: nil
            )
            event.calendarItemID = title
            return event
        }
        let review = event("Design review", at(13), at(13, 45), blue, location: "Studio 3")
        let state = await StateFixture.make(at: at(13, 12)) { store, _ in
            store.add(event("Halloween", TestSupport.date(2026, 10, 31), TestSupport.date(2026, 11, 1), orange, allDay: true))
            store.add(event("Lunch with Priya", at(12), at(12, 50), green, location: "Tartine"))
            store.add(review, link: "https://meet.google.com/abc-defg-hij https://www.figma.com/file/orbit")
            store.add(event("Ship v1.0", at(15), at(16), pink))
            store.add(event("Climbing", at(18, 30), at(20), green, location: "Mission Cliffs"))
            store.add(event("Day of the Dead", TestSupport.date(2026, 11, 1), TestSupport.date(2026, 11, 2), orange, allDay: true))
            store.add(event("Flight to Lisbon", TestSupport.date(2026, 11, 1, 9, 40), TestSupport.date(2026, 11, 1, 17, 55), blue, location: "SFO Terminal 2"))
            store.add(event("Dentist", at(9, day: 27), at(10, day: 27), blue))
            store.add(event("Book club", at(19, day: 22), at(21, day: 22), pink))
            store.add(event("Run", at(7, day: 24), at(8, day: 24), green))
        }.state
        state.preferences.showYearProgress = true
        state.preferences.showDayProgress = true
        // The Day view is what a fresh install opens on; the agenda is the other option.
        for view in [EventsView.day, .agenda] {
            state.preferences.eventsView = view
            for scheme in [ColorScheme.light, .dark] {
                attach(render(state, scheme: scheme), "Screenshot \(view.rawValue) \(scheme == .dark ? "dark" : "light")")
            }
        }

        var detail = review
        detail.meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")
        detail.links = [URL(string: "https://www.figma.com/file/orbit")!]
        detail.notes = "Walk through the v1.0 popover and settings. Mockups: https://www.figma.com/file/orbit"
        detail.guests = [
            Guest(name: "Janak", response: .accepted, isOrganizer: true, isYou: true),
            Guest(name: "Priya", response: .accepted),
            Guest(name: "Sam", response: .tentative),
        ]
        for scheme in [ColorScheme.light, .dark] {
            let root = EventDetailView(event: detail)
                .environment(state)
                .background(scheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, scheme)
                .environment(\.timeZone, TestSupport.utc)
                .environment(\.calendar, state.calendar)
            let host = NSHostingView(rootView: root)
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            attach(snapshot(host), "Screenshot detail \(scheme == .dark ? "dark" : "light")")
        }
    }

    func testSettingsWindow() async {
        let state = await makeState()
        for scheme in [ColorScheme.light, .dark] {
            state.preferences.showYearProgress = true
            let root = SettingsView()
                .environment(state)
                .environment(\.colorScheme, scheme)
                // Draw as the frontmost window, so controls show their active colors.
                .environment(\.controlActiveState, .key)
                .environment(\.timeZone, TestSupport.utc)
                .frame(width: 1000, height: 860)
            let host = NSHostingView(rootView: root)
            host.frame.size = CGSize(width: 1000, height: 860)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            attach(snapshot(host), "Settings window (\(scheme == .dark ? "dark" : "light"))")
        }
    }

    /// Each Settings pane in the full window, light and dark, to check the sidebar, sections and switches.
    func testSettingsPanes() async {
        let state = await StateFixture.make { store, preferences in
            store.calendarList = [
                StateFixture.calendarInfo("work", source: "Google"),
                StateFixture.calendarInfo("home"),
                StateFixture.calendarInfo("family"),
            ]
            preferences.showYearProgress = true
        }.state
        UserDefaults.standard.removeObject(forKey: "settingsPane")
        defer { UserDefaults.standard.removeObject(forKey: "settingsPane") }
        for scheme in [ColorScheme.light, .dark] {
            for pane in SettingsPane.allCases where scheme == .light || pane == .general {
                UserDefaults.standard.set(pane.rawValue, forKey: "settingsPane")
                let root = SettingsView()
                    .environment(state)
                    .environment(\.colorScheme, scheme)
                    .environment(\.controlActiveState, .key)
                    .environment(\.timeZone, TestSupport.utc)
                    .frame(width: 1000, height: 860)
                let host = NSHostingView(rootView: root)
                host.frame.size = CGSize(width: 1000, height: 860)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                try? await Task.sleep(for: .milliseconds(300))
                attach(snapshot(host), "Settings \(pane.rawValue) (\(scheme == .dark ? "dark" : "light"))")
            }
        }
    }

    /// The sidebar on its own: offscreen, the split view doesn't draw its material or anything on it.
    func testSettingsSidebar() {
        for scheme in [ColorScheme.light, .dark] {
            let root = SettingsSidebar(navigation: SettingsNavigation(pane: .general))
                .tint(.orbitTeal)
                .environment(\.colorScheme, scheme)
                .frame(width: 210, height: 420)
                .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
            let host = NSHostingView(rootView: root)
            host.frame.size = CGSize(width: 210, height: 420)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            attach(snapshot(host), "Settings sidebar (\(scheme == .dark ? "dark" : "light"))")
        }
    }

    /// Settings › Display with the Icon style picked, to check the menu bar section isn't crowded.
    func testDisplayPane() async {
        let state = await makeState()
        state.preferences.menuBarFormat.preset = .icon
        let root = DisplaySettingsTab()
            .environment(state)
            .frame(width: 560, height: 420)
        let host = NSHostingView(rootView: root)
        host.frame.size = CGSize(width: 560, height: 420)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        attach(snapshot(host), "Display pane")
    }

    /// Every page of the welcome tour, in light and dark, plus the calendar page before access is granted.
    func testWelcomeTour() async {
        let state = await makeState()
        for scheme in [ColorScheme.light, .dark] {
            for step in OnboardingStep.allCases {
                let rep = renderTour(state, step: step, scheme: scheme)
                attach(rep, "Tour \(step.rawValue + 1) \(step) (\(scheme == .dark ? "dark" : "light"))")
                XCTAssertEqual(rep.size.width, 720)
            }
        }
        let (fresh, freshStore, _) = await StateFixture.make()
        freshStore.access = .notDetermined
        fresh.refreshCalendars()
        attach(renderTour(fresh, step: .calendars, scheme: .light), "Tour calendars, before access")
        let denied = await StateFixture.make { store, _ in store.access = .denied }.state
        attach(renderTour(denied, step: .calendars, scheme: .light), "Tour calendars, access off")
    }

    private func renderTour(_ state: AppState, step: OnboardingStep, scheme: ColorScheme) -> NSBitmapImageRep {
        let root = OnboardingView(step: step, finish: { _ in })
            .environment(state)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: root)
        host.frame.size = CGSize(width: 720, height: 560)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        // The previews load their sample events in a task.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return snapshot(host)
    }

    /// Settings › Help with a couple of answers open.
    func testHelpPane() async {
        let state = await makeState()
        let root = HelpSettingsTab()
            .environment(state)
            .frame(width: 600, height: 900)
        let host = NSHostingView(rootView: root)
        host.frame.size = CGSize(width: 600, height: 900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        let rep = snapshot(host)
        attach(rep, "Help pane")
        XCTAssertGreaterThan(rep.pixelsHigh, 100)
    }

    /// Every option that adds height, at once: the Settings preview must still fit its panel.
    func testSettingsPreviewFitsWithEverythingOn() async {
        let state = await makeState()
        let preferences = state.preferences
        preferences.textSize = .extraLarge
        preferences.calendarDensity = .airy
        preferences.eventDensity = .airy
        preferences.showDaySummary = true
        preferences.showYearProgress = true
        preferences.showDayProgress = true
        preferences.showWeekNumbers = true
        preferences.showFreeTime = true
        preferences.showMonthGrid = true
        preferences.eventDots = .colors
        preferences.agendaDayCount = 30
        preferences.hideEmptyDays = false
        let root = SettingsView()
            .environment(state)
            .environment(\.controlActiveState, .key)
            .frame(width: 1000, height: 860)
        let host = NSHostingView(rootView: root)
        host.frame.size = CGSize(width: 1000, height: 860)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        // The preview builds its demo state in a task, then measures and scales on the next pass.
        for _ in 0..<4 {
            _ = snapshot(host)
            try? await Task.sleep(for: .milliseconds(100))
        }
        attach(snapshot(host), "Settings preview, everything on")
    }

    func testNewEventForm() async {
        let state = await makeState()
        state.mode = .newEvent
        let rep = render(state)
        attach(rep, "New event form")
        XCTAssertGreaterThan(rep.pixelsHigh, 300)
    }

    func testDarkAppearance() async {
        let state = await makeState()
        let light = render(state, scheme: .light)
        let dark = render(state, scheme: .dark)
        attach(light, "Appearance = light")
        attach(dark, "Appearance = dark")
        XCTAssertNotEqual(png(light), png(dark))
    }
}
