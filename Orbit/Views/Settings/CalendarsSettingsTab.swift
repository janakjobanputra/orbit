import SwiftUI

struct CalendarsSettingsTab: View {

    @Environment(AppState.self) private var appState
    @State private var isHelpExpanded = false

    var body: some View {
        @Bindable var preferences = appState.preferences

        Form {
            Section("Help") {
                DisclosureGroup(isExpanded: $isHelpExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Orbit shows the calendars your Mac already syncs. Add Google, Exchange or other accounts in System Settings › Internet Accounts, then turn their calendars on below.")
                        Text("If no calendars appear at all, Orbit may not have calendar access.")
                        HStack {
                            Button("Internet Accounts") {
                                open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                            }
                            Button("Privacy Settings") {
                                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                            }
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                } label: {
                    // The whole row toggles, not just the chevron.
                    Button {
                        withAnimation { isHelpExpanded.toggle() }
                    } label: {
                        Text("Why don't I see my events?")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Default calendar") {
                Picker(selection: $preferences.defaultCalendarID) {
                    Text("System default").tag(String?.none)
                    ForEach(appState.writableCalendars) { info in
                        Text("\(info.title) (\(info.sourceTitle))").tag(Optional(info.id))
                    }
                } label: {
                    Text("New events go to")
                }
            }

            Section {
                TextField("Ignore titles containing", text: $preferences.ignoredTitleKeywords, prompt: Text("daycare, school run"))
            } header: {
                Text("Event filters")
            } footer: {
                Text("Comma-separated words. Matching events are hidden from the menu bar and the agenda.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Maps") {
                Picker("Open locations in", selection: $preferences.mapsProvider) {
                    ForEach(MapsProvider.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            CalendarListSection()
        }
        .formStyle(.grouped)
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

private struct CalendarListSection: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        let preferences = appState.preferences
        let calendars = appState.calendars
        let selected = calendars.filter { preferences.isCalendarVisible($0.id) }.count
        let sources = Dictionary(grouping: calendars, by: \.sourceTitle).sorted { $0.key < $1.key }

        Section {
            if calendars.isEmpty {
                Text("No calendars available")
                    .foregroundStyle(.secondary)
            }
            ForEach(sources, id: \.key) { source, group in
                Text(source.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                }
            }
        } header: {
            HStack {
                Text("Show calendars")
                Spacer()
                Text("\(selected) of \(calendars.count) selected")
                    .foregroundStyle(.secondary)
                Button("All") { preferences.showAllCalendars() }
                Button("None") { preferences.hideAllCalendars(calendars.map(\.id)) }
            }
            .buttonStyle(.link)
        }
    }
}
