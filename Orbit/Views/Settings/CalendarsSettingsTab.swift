import SwiftUI

struct CalendarsSettingsTab: View {

    @Environment(AppState.self) private var appState
    @State private var isHelpExpanded = false

    var body: some View {
        @Bindable var preferences = appState.preferences

        SettingsPage {
            SettingsSection("Help") {
                SettingsDisclosureRow(question: "Why don't I see my events?", isExpanded: $isHelpExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Orbit shows the calendars your Mac already syncs. Add Google, Exchange or other accounts in System Settings › Internet Accounts, then turn their calendars on below.")
                        Text("If no calendars appear at all, Orbit may not have calendar access.")
                        HStack {
                            Button("Internet Accounts") { NSWorkspace.shared.open(SystemSettingsPane.internetAccounts) }
                            Button("Privacy Settings") { NSWorkspace.shared.open(SystemSettingsPane.calendarPrivacy) }
                        }
                    }
                }
            }

            SettingsSection("Default calendar") {
                SettingsMenuPicker(title: "New events go to", selection: $preferences.defaultCalendarID) {
                    Text("System default").tag(String?.none)
                    ForEach(appState.writableCalendars) { info in
                        Text("\(info.title) (\(info.sourceTitle))").tag(Optional(info.id))
                    }
                }
            }

            SettingsSection("Event filters", footer: "Comma-separated words. Matching events are hidden from the menu bar and the agenda.") {
                SettingsRow(title: "Ignore titles containing") {
                    TextField("Ignore titles containing", text: $preferences.ignoredTitleKeywords, prompt: Text("daycare, school run"))
                        .labelsHidden()
                        .frame(width: 220)
                }
            }

            SettingsSection("Maps") {
                SettingsSegmentedPicker(title: "Open locations in", selection: $preferences.mapsProvider) {
                    ForEach(MapsProvider.allCases) { Text($0.label).tag($0) }
                }
            }

            CalendarListSection()
        }
    }
}

private struct CalendarListSection: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        let preferences = appState.preferences
        let calendars = appState.calendars
        let selected = calendars.filter { preferences.isCalendarVisible($0.id) }.count
        let sources = Dictionary(grouping: calendars, by: \.sourceTitle).sorted { $0.key < $1.key }

        SettingsSection(title: "Show calendars") {
            HStack(spacing: 8) {
                Text("\(selected) of \(calendars.count) selected")
                    .foregroundStyle(.secondary)
                Button("All") { preferences.showAllCalendars() }
                Button("None") { preferences.hideAllCalendars(calendars.map(\.id)) }
            }
            .buttonStyle(.link)
        } content: {
            if calendars.isEmpty {
                SettingsRow(title: "No calendars available") { EmptyView() }
            }
            ForEach(sources, id: \.key) { source, group in
                Text(source.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(group) { info in
                    Toggle(isOn: Binding(
                        get: { preferences.isCalendarVisible(info.id) },
                        set: { preferences.setCalendar(info.id, visible: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(info.color.color)
                                .frame(width: 8, height: 8)
                            Text(info.title)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }
}
