import SwiftUI

struct DisplaySettingsTab: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var preferences = appState.preferences

        SettingsPage {
            MenuBarSection()

            SettingsSection("Calendar display") {
                SettingsToggle("Day summary", isOn: $preferences.showDaySummary)
                SettingsToggle("Show free time", detail: "Gaps of 30 minutes or more between 9am and 6pm.", isOn: $preferences.showFreeTime)
                SettingsToggle("Year progress bar", isOn: $preferences.showYearProgress)
                SettingsToggle("Day progress bar", isOn: $preferences.showDayProgress)
                SettingsToggle("Week numbers", isOn: $preferences.showWeekNumbers)
                SettingsToggle("Highlight today", isOn: $preferences.highlightToday)
                SettingsToggle("Dim weekends", isOn: $preferences.dimWeekends)
                SettingsToggle("Event dots", isOn: Binding(
                    get: { preferences.eventDots != .off },
                    set: { preferences.eventDots = $0 ? .colors : .off }
                ))
                if preferences.eventDots != .off {
                    SettingsMenuPicker(title: "Dot style", selection: $preferences.eventDots) {
                        ForEach(EventDotsStyle.onStyles) { Text($0.label).tag($0) }
                    }
                }
                SettingsSegmentedPicker(title: "Week starts on", selection: $preferences.weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.label).tag($0) }
                }
            }

            SettingsSection("Layout") {
                SettingsSegmentedPicker(title: "Events view", selection: $preferences.eventsView) {
                    ForEach(EventsView.allCases) { Text($0.label).tag($0) }
                }
                SettingsSegmentedPicker(title: "Text size", selection: $preferences.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                SettingsSegmentedPicker(title: "Calendar", selection: $preferences.calendarDensity) {
                    ForEach(Density.allCases) { Text($0.label).tag($0) }
                }
                SettingsSegmentedPicker(title: "Events", selection: $preferences.eventDensity) {
                    ForEach(Density.allCases) { Text($0.label).tag($0) }
                }
                if preferences.eventsView == .agenda {
                    SettingsMenuPicker(title: "Agenda days", selection: $preferences.agendaDayCount) {
                        ForEach(Preferences.agendaDayOptions, id: \.self) { count in
                            Text(count == 1 ? "1 day" : "\(count) days").tag(count)
                        }
                    }
                    SettingsToggle("Hide empty days", isOn: $preferences.hideEmptyDays)
                }
                SettingsToggle("Hide all-day events", isOn: $preferences.hideAllDayEvents)
                SettingsToggle("Hide past events", isOn: $preferences.hidePastEvents)
                SettingsToggle("Show declined events", detail: "Crossed out. Invitations you haven't answered or said maybe to are always shown, marked as such.", isOn: $preferences.showDeclinedEvents)
            }
        }
    }
}

private struct MenuBarSection: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var preferences = appState.preferences
        let format = preferences.menuBarFormat

        SettingsSection("Menu bar") {
            SettingsMenuPicker(title: "Style", detail: format.preset.summary, selection: $preferences.menuBarFormat.preset) {
                ForEach(MenuBarPreset.allCases) { Text($0.label).tag($0) }
            }

            if format.preset == .custom {
                TokenEditor(tokens: $preferences.menuBarFormat.customTokens)
            }

            if format.tokens.contains(.date) {
                SettingsMenuPicker(title: "Date format", selection: $preferences.menuBarFormat.datePattern) {
                    ForEach(datePatternOptions(current: format.datePattern), id: \.self) { pattern in
                        Text(sample(for: pattern)).tag(pattern)
                    }
                }
            }

            if format.tokens.contains(.time) {
                SettingsRow(title: "Time format") {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("Time format", text: $preferences.menuBarFormat.timePattern, prompt: Text(MenuBarFormat.defaultTimePattern))
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            .frame(width: 140)
                        Link("Learn format codes", destination: URL(string: "https://unicode-org.github.io/icu/userguide/format_parse/datetime/")!)
                            .font(.caption)
                            .foregroundStyle(Color.orbitTeal)
                    }
                }
                SettingsSegmentedPicker(title: "Clock", selection: Binding(
                    get: { preferences.menuBarFormat.uses24HourTime },
                    set: { preferences.menuBarFormat.setUses24HourTime($0) }
                )) {
                    Text("12h").tag(false)
                    Text("24h").tag(true)
                }
            }

            if format.tokens.count > 1 {
                SettingsSegmentedPicker(title: "Separator", selection: $preferences.menuBarFormat.separator) {
                    ForEach(SeparatorStyle.allCases) { Text($0.label).tag($0) }
                }
            }

            if format.tokens.contains(.nextEvent) {
                SettingsRow(title: "Show the next event \(preferences.nextEventLeadMinutes) minutes before it starts") {
                    Stepper("Lead time", value: $preferences.nextEventLeadMinutes, in: 5...120, step: 5)
                        .labelsHidden()
                }
            }
        }
    }

    /// The preset patterns, plus the current one if the user typed something else.
    private func datePatternOptions(current: String) -> [String] {
        MenuBarFormat.datePatterns.contains(current) ? MenuBarFormat.datePatterns : MenuBarFormat.datePatterns + [current]
    }

    private func sample(for pattern: String) -> String {
        var format = appState.preferences.menuBarFormat
        format.datePattern = pattern
        return MenuBarFormatter(format: format, leadMinutes: 0, calendar: appState.calendar).dateText(appState.now)
    }
}

/// Chips for the custom menu bar layout: remove with ×, add with +.
private struct TokenEditor: View {

    @Binding var tokens: [MenuBarToken]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tokens) { token in
                HStack(spacing: 4) {
                    Label(token.label, systemImage: token.symbol)
                    Button {
                        tokens.removeAll { $0 == token }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(token.label)")
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            let missing = MenuBarToken.allCases.filter { !tokens.contains($0) }
            if !missing.isEmpty {
                Menu {
                    ForEach(missing) { token in
                        Button(token.label, systemImage: token.symbol) { tokens.append(token) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Add item")
            }
            Spacer(minLength: 0)
        }
    }
}
