import SwiftUI

struct DisplaySettingsTab: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var preferences = appState.preferences

        Form {
            MenuBarSection()

            Section("Calendar display") {
                Toggle("Day summary", isOn: $preferences.showDaySummary)
                Toggle(isOn: $preferences.showFreeTime) {
                    Text("Show free time")
                    Text("Gaps of 30 minutes or more between 9am and 6pm.")
                }
                Toggle("Year progress bar", isOn: $preferences.showYearProgress)
                Toggle("Day progress bar", isOn: $preferences.showDayProgress)
                Toggle("Week numbers", isOn: $preferences.showWeekNumbers)
                Toggle("Highlight today", isOn: $preferences.highlightToday)
                Toggle("Dim weekends", isOn: $preferences.dimWeekends)
                Toggle("Event dots", isOn: Binding(
                    get: { preferences.eventDots != .off },
                    set: { preferences.eventDots = $0 ? .colors : .off }
                ))
                if preferences.eventDots != .off {
                    Picker("Dot style", selection: $preferences.eventDots) {
                        ForEach(EventDotsStyle.onStyles) { Text($0.label).tag($0) }
                    }
                }
                Picker("Week starts on", selection: $preferences.weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Layout") {
                Picker("Events view", selection: $preferences.eventsView) {
                    ForEach(EventsView.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Text size", selection: $preferences.textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Calendar", selection: $preferences.calendarDensity) {
                    ForEach(Density.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Events", selection: $preferences.eventDensity) {
                    ForEach(Density.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.eventsView == .agenda {
                    Picker("Agenda days", selection: $preferences.agendaDayCount) {
                        ForEach(Preferences.agendaDayOptions, id: \.self) { count in
                            Text(count == 1 ? "1 day" : "\(count) days").tag(count)
                        }
                    }
                    Toggle("Hide empty days", isOn: $preferences.hideEmptyDays)
                }
                Toggle("Hide all-day events", isOn: $preferences.hideAllDayEvents)
                Toggle("Hide past events", isOn: $preferences.hidePastEvents)
                Toggle(isOn: $preferences.showDeclinedEvents) {
                    Text("Show declined events")
                    Text("Crossed out. Invitations you haven't answered or said maybe to are always shown, marked as such.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MenuBarSection: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var preferences = appState.preferences
        let format = preferences.menuBarFormat

        Section("Menu bar") {
            Picker(selection: $preferences.menuBarFormat.preset) {
                ForEach(MenuBarPreset.allCases) { Text($0.label).tag($0) }
            } label: {
                Text("Style")
                Text(format.preset.summary)
            }

            if format.preset == .custom {
                TokenEditor(tokens: $preferences.menuBarFormat.customTokens)
            }

            if format.tokens.contains(.date) {
                Picker("Date format", selection: $preferences.menuBarFormat.datePattern) {
                    ForEach(datePatternOptions(current: format.datePattern), id: \.self) { pattern in
                        Text(sample(for: pattern)).tag(pattern)
                    }
                }
            }

            if format.tokens.contains(.time) {
                LabeledContent("Time format") {
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
                Picker("Clock", selection: Binding(
                    get: { preferences.menuBarFormat.uses24HourTime },
                    set: { preferences.menuBarFormat.setUses24HourTime($0) }
                )) {
                    Text("12h").tag(false)
                    Text("24h").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if format.tokens.count > 1 {
                Picker("Separator", selection: $preferences.menuBarFormat.separator) {
                    ForEach(SeparatorStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if format.tokens.contains(.nextEvent) {
                Stepper(value: $preferences.nextEventLeadMinutes, in: 5...120, step: 5) {
                    Text("Show the next event \(preferences.nextEventLeadMinutes) minutes before it starts")
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
