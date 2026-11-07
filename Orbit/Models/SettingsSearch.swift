import Foundation

/// One thing you can find with the search field in Settings.
struct SettingsSearchEntry: Identifiable, Hashable {

    let pane: SettingsPane
    /// The section heading it sits under, which search results scroll to.
    let section: String?
    let title: String
    var detail: String?
    /// Other words someone might search for.
    var keywords: String = ""
    /// A Help question to open when this result is chosen.
    var helpQuestion: String?

    var id: String { "\(pane.rawValue)/\(section ?? "")/\(title)" }

    /// "Display › Layout".
    var location: String {
        [pane.title, section].compactMap { $0 }.joined(separator: " › ")
    }
}

enum SettingsSearch {

    /// Entries that match every word typed, best first: titles starting with the search, then titles containing it,
    /// then everything else, with settings ahead of Help answers.
    static func results(for query: String, in entries: [SettingsSearchEntry] = index) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        func rank(_ entry: SettingsSearchEntry) -> Int {
            let title = entry.title.lowercased()
            let base = title.hasPrefix(trimmed) ? 0 : title.contains(trimmed) ? 1 : 2
            return base + (entry.helpQuestion == nil ? 0 : 3)
        }

        let matches = entries.filter { entry in
            let text = [entry.title, entry.detail ?? "", entry.section ?? "", entry.pane.title, entry.keywords]
                .joined(separator: " ")
                .lowercased()
            return words.allSatisfy(text.contains)
        }
        // Sorting by rank alone keeps the index's own order within each rank.
        return matches.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    static let index: [SettingsSearchEntry] = settings + HelpTopic.all.map {
        SettingsSearchEntry(pane: .help, section: $0.group.rawValue, title: $0.question, detail: nil, keywords: $0.answer, helpQuestion: $0.question)
    }

    private static func entry(_ pane: SettingsPane, _ section: String?, _ title: String, _ detail: String? = nil, keywords: String = "") -> SettingsSearchEntry {
        SettingsSearchEntry(pane: pane, section: section, title: title, detail: detail, keywords: keywords)
    }

    /// Every setting, in the order the panes show them. Add to this when adding a setting.
    private static let settings: [SettingsSearchEntry] = [
        entry(.general, "Startup", "Launch at login", keywords: "start open automatically login item"),
        entry(.general, "Startup", "Keep calendar on top", "The calendar stays open until you click the menu bar item again.", keywords: "pin float"),
        entry(.general, "Theme", "Appearance", keywords: "dark light system mode theme"),
        entry(.general, "Shortcuts", "Enable global shortcuts", keywords: "hotkey keyboard"),
        entry(.general, "Shortcuts", "Toggle calendar", keywords: "shortcut hotkey keyboard open"),
        entry(.general, "Shortcuts", "Join next meeting", keywords: "shortcut hotkey keyboard video call"),
        entry(.general, "Shortcuts", "Calendar shortcuts", keywords: "keyboard hotkey"),
        entry(.general, "Updates", "Check for updates automatically", keywords: "version new release"),
        entry(.general, "Privacy", "Share anonymous usage stats", "Off unless you turn it on.", keywords: "analytics metrics telemetry data tracking"),
        entry(.general, "Privacy", "Send crash reports", keywords: "diagnostics bug telemetry data"),
        entry(.general, "Custom video services", "Custom video services", "Links to these domains get a Join button.", keywords: "meeting call zoom meet teams webex"),

        entry(.display, "Menu bar", "Style", "Classic, Minimal, Agenda, Info, Icon or Custom.", keywords: "logo clock date time next meeting"),
        entry(.display, "Menu bar", "Date format", keywords: "menu bar"),
        entry(.display, "Menu bar", "Time format", keywords: "menu bar seconds pattern"),
        entry(.display, "Menu bar", "Clock", "12h or 24h.", keywords: "24 hour military am pm"),
        entry(.display, "Menu bar", "Separator", keywords: "dot dash bar space"),
        entry(.display, "Menu bar", "Show the next event before it starts", keywords: "lead time minutes"),
        entry(.display, "Calendar display", "Day summary"),
        entry(.display, "Calendar display", "Show free time", "Gaps of 30 minutes or more between 9am and 6pm.", keywords: "busy available"),
        entry(.display, "Calendar display", "Year progress bar"),
        entry(.display, "Calendar display", "Day progress bar"),
        entry(.display, "Calendar display", "Week numbers"),
        entry(.display, "Calendar display", "Highlight today"),
        entry(.display, "Calendar display", "Dim weekends", keywords: "saturday sunday"),
        entry(.display, "Calendar display", "Event dots", keywords: "dot style colors month grid"),
        entry(.display, "Calendar display", "Week starts on", keywords: "sunday monday first day"),
        entry(.display, "Layout", "Events view", "Day or Agenda.", keywords: "timeline list"),
        entry(.display, "Layout", "Text size", keywords: "font bigger smaller large"),
        entry(.display, "Layout", "Calendar spacing", keywords: "density compact cozy airy month"),
        entry(.display, "Layout", "Events spacing", keywords: "density compact cozy airy zoom hour height"),
        entry(.display, "Layout", "Agenda days", keywords: "how many days ahead"),
        entry(.display, "Layout", "Hide empty days", keywords: "agenda"),
        entry(.display, "Layout", "Hide all-day events"),
        entry(.display, "Layout", "Hide past events", keywords: "finished"),
        entry(.display, "Layout", "Show declined events", "Crossed out.", keywords: "invitation rejected"),

        entry(.calendars, "Default calendar", "New events go to", keywords: "default calendar create"),
        entry(.calendars, "Event filters", "Ignore titles containing", keywords: "hide filter keywords"),
        entry(.calendars, "Maps", "Open locations in", keywords: "apple google maps directions"),
        entry(.calendars, "Show calendars", "Show calendars", "Choose which calendars appear.", keywords: "hide accounts google icloud outlook exchange"),

        entry(.backup, "Settings file", "Export settings", "Save your settings to a file.", keywords: "backup json save copy"),
        entry(.backup, "Settings file", "Import settings", "Replace your settings with the ones in a file.", keywords: "restore json load another mac"),

        entry(.help, nil, "Take the Tour", keywords: "welcome onboarding tutorial"),
        entry(.about, nil, "Check for Updates", keywords: "version release download"),
        entry(.about, nil, "Source code on GitHub", keywords: "license open source"),
    ]
}

/// Where the Settings window is: the open page, the pages behind and ahead of it, and any search.
@MainActor
@Observable
final class SettingsNavigation {

    private(set) var pane: SettingsPane
    private var backStack: [SettingsPane] = []
    private var forwardStack: [SettingsPane] = []

    var query = ""
    /// The section to scroll to, taken by the page once it has.
    var requestedSection: String?
    /// The Help question to open, taken by the Help page once it has.
    var requestedHelpQuestion: String?

    init(pane: SettingsPane) {
        self.pane = pane
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Opens a page from the sidebar, ending any search. Opening the page you're on adds nothing to the history.
    func open(_ page: SettingsPane) {
        query = ""
        guard page != pane else { return }
        backStack.append(pane)
        forwardStack.removeAll()
        pane = page
    }

    /// Opens a search result on its page, scrolled to its section.
    func open(_ result: SettingsSearchEntry) {
        requestedSection = result.section
        requestedHelpQuestion = result.helpQuestion
        open(result.pane)
    }

    func goBack() {
        query = ""
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(pane)
        pane = previous
    }

    func goForward() {
        query = ""
        guard let next = forwardStack.popLast() else { return }
        backStack.append(pane)
        pane = next
    }
}
