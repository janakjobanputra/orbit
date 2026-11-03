# Settings verification

Every setting in Orbit's Settings window, each of its options, and how it is checked.

- **Behaviour** tests drive the setting through `AppState` with a fake calendar store and a fixed clock (Sat 31 Oct 2026, 9:47), then check what the menu bar, agenda, month grid and search would show. See `OrbitTests/SettingsBehaviorTests.swift`.
- **Render** tests draw the real popover once per option, fail if two options look the same, and attach the images to the test results. See `OrbitTests/PopoverRenderingTests.swift`.
- **Persist** tests save every option of every setting and read it back as on a relaunch (`SettingsPersistenceTests`).
- **Manual** items need macOS permission prompts or real keystrokes, so they're checked by hand in the running app.

Run everything with `make test`. To look at the rendered popovers, run the tests with `-resultBundlePath`, then `xcrun xcresulttool export attachments`.

## General

| Setting | Options | Checked by | Result |
|---|---|---|---|
| Launch at login | on, off | Manual: toggle, then look for Orbit in System Settings › General › Login Items | pass (manual; restart not yet tried) |
| Keep calendar on top | on, off | Behaviour (`testKeepCalendarOnTop`); Manual: popover stays open when clicking elsewhere | pass |
| Appearance | System, Light, Dark | Behaviour (`testAppearanceOptions`), Render (`testDarkAppearance`) | pass |
| Enable global shortcuts | on, off | Behaviour (`testEnableGlobalShortcuts`) | pass |
| Toggle calendar shortcut | default ⇧⌘C, re-recordable | Behaviour (`testGlobalShortcutDefaults`); Manual: press it anywhere | pass (manual) |
| Join next meeting shortcut | default ⇧⌘J, re-recordable | Behaviour (`testGlobalShortcutDefaults`, `testJoinNextMeetingPicksMeetingInProgressOrNext`, `testJoinStillWorksAfterTheMeetingStarts`); Manual: press it with a meeting coming up | upcoming passes; in progress being rechecked |
| Calendar shortcuts › Show… | popover list | Manual | pass (manual) |
| Custom video services | add, remove | Behaviour (`testCustomVideoServiceAddsJoinLinks`, `testCustomServiceHostFromLinkOrDomain`) | pass |
| Check for updates automatically | on (default), off | Behaviour (`UpdateCheckerTests`: once a day, survives relaunch, manual check, failure); Render (`testUpdateBanner`); Manual: About › Check for Updates against the live GitHub release | automated pass; manual not yet tried |

## Display › Menu bar

| Setting | Options | Checked by | Result |
|---|---|---|---|
| Style | Classic, Minimal, Agenda (and its fallback), Info, Custom | Behaviour (`testPreset*`) | pass |
| Custom items | Date, Time, Next Event, Week Number, any order, none | Behaviour (`testCustomTokensEachRender`, `testCustomWithNoTokensFallsBackToDateAndTime`) | pass |
| Date format | every preset pattern | Behaviour (`testEveryDateFormatRendersDifferently`) | pass |
| Time format | free text, e.g. `h:mm a` | Behaviour (`testTimeFormatAnd24HourClock`) | pass |
| Clock | 12h, 24h | Behaviour (`testTimeFormatAnd24HourClock`) | pass |
| Separator | \|, ·, —, space | Behaviour (`testEverySeparator`) | pass |
| Show next event … minutes before | 5–120 | Behaviour (`testNextEventLeadTime`) | pass |

## Display › Calendar display

| Setting | Options | Checked by | Result |
|---|---|---|---|
| Day summary | on, off | Behaviour (`testDaySummaryCountsVisibleEvents`), Render | pass |
| Show free time | on, off | Behaviour (`testShowFreeTime`), Render | pass |
| Year progress bar | on, off | Render, plus `testYearProgressThroughTheYear` (1 Jan to 31 Dec 23:59) and the `YearProgressTests` label tests (leap year, last day, never rounds up to 100%) | pass |
| Day progress bar | on, off | Render | pass |
| Week numbers | on, off | Render | pass |
| Highlight today | on, off | Render | pass |
| Dim weekends | on, off | Render | pass |
| Event dots | on, off; when on: Single dot, Calendar colors | Behaviour (`testEventDotColoursAreDistinctAndCapped`), Render | pass |
| Week starts on | Sun, Mon | Behaviour (`testWeekStartsOn`), Render | pass |
| Show month (⌘M in the popover) | shown, hidden | Behaviour, Render | pass |

## Display › Layout

| Setting | Options | Checked by | Result |
|---|---|---|---|
| Events view | Day (default), Agenda | Behaviour (`DayTimelineTests`: layout, overlaps, midnight, saved choice), Render (`testDayView`) | pass |
| Text size | Small, Default, Large, XL | Render (each draws differently; popover width is 270, 300, 336, 375 pt) | pass |
| Calendar spacing | Compact, Cozy, Airy | Behaviour (`testDensityOptionsGrowInOrder`), Render | pass |
| Events spacing | Compact, Cozy, Airy | Behaviour, Render | pass |
| Agenda days | 1, 2, 3, 5, 7, 14, 30 | Behaviour (`testEveryAgendaLength`, `testAgendaLengthCutsOffLaterEvents`) | pass |
| Hide empty days | on, off | Behaviour (`testHideEmptyDays`) | pass |
| Hide all-day events | on, off | Behaviour (`testHideAllDayEvents`), Render | pass |
| Hide past events | on, off | Behaviour (`testHidePastEvents`), Render | pass |

## Calendars

| Setting | Options | Checked by | Result |
|---|---|---|---|
| Why don't I see my events? | Internet Accounts, Privacy Settings buttons | Manual: each opens the right System Settings page | pass (manual) |
| New events go to | System default, any writable calendar | Behaviour (`testDefaultCalendarForNewEvents`) | pass |
| Ignore titles containing | comma-separated words | Behaviour (`testIgnoreTitlesContaining`, `testTitleFilter*`) | pass |
| Open locations in | Apple Maps, Google Maps | Behaviour (`testMapsProviderLinks`, `testMapsLinks`); Manual: click a location | pass |
| Calendar list | each calendar on/off | Behaviour (`testCalendarToggles`) | pass |
| All / None | show all, hide all | Behaviour (`testAllAndNoneButtons`) | pass |

## Everywhere

| What | Checked by | Result |
|---|---|---|
| Every option of every setting survives a relaunch | Persist (`SettingsPersistenceTests`) | pass |
| Settings opens without crashing, on every pane | Manual launch with `-OpenSettingsOnLaunch YES -settingsPane <pane>` | pass |
| Preview matches the popover | Shares `PopoverView` with the real popover | pass |

## Found while verifying

- The agenda's day headings and event times used the Mac's time zone instead of the app's calendar. That's harmless in normal use, but it is now consistent with the rest of the popover.
- With Event dots set to Off, the month rows lose the space the dots used, so the popover gets a little shorter. Not changed.
- The new-event form had no way to add a meeting link, so ⇧⌘J couldn't be tried on events made in Orbit. It now has Location, Link and Notes (`testNewEventWithLinkCanBeJoined`, `testNewEventLinkParsing`).
- "Why don't I see my events?" only expanded from its chevron. The whole row now toggles it.
