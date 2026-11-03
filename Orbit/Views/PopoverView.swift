import SwiftUI

struct PopoverView: View {

    @Environment(AppState.self) private var appState
    let openSettings: () -> Void
    var close: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if appState.access == .granted {
                HeaderBar(openSettings: openSettings)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                content
            } else {
                AccessRequiredView()
                    .padding(20)
            }
        }
        .frame(width: 300 * appState.preferences.textSize.scale)
        .environment(\.textScale, appState.preferences.textSize.scale)
        .tint(.orbitTeal)
        .background { shortcuts }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.mode {
        case .agenda:
            CalendarPanel()
        case .search:
            Divider()
            SearchView()
        case .newEvent:
            Divider()
            NewEventView()
        }
    }

    /// Keyboard shortcuts for actions without a visible button of their own.
    private var shortcuts: some View {
        Group {
            Button("Today") { appState.showToday() }
                .keyboardShortcut("t", modifiers: .command)
            // Search and the new-event form have their own Cancel, which goes back to the agenda first.
            if appState.mode == .agenda {
                Button("Close") {
                    if !appState.handleEscape() { close() }
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything below the header in agenda mode. Also used, non-interactively, as the Settings preview.
struct CalendarPanel: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        let preferences = appState.preferences
        let hasTopSection = preferences.showDaySummary || preferences.showMonthGrid
        let hasProgress = preferences.showYearProgress || preferences.showDayProgress
        VStack(spacing: 0) {
            if hasTopSection {
                VStack(spacing: 14) {
                    if preferences.showDaySummary {
                        Text(appState.daySummary.text)
                            .orbitFont(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if preferences.showMonthGrid {
                        VStack(spacing: 10) {
                            MonthHeaderView()
                            MonthGridView()
                        }
                        .padding(10)
                        .background {
                            // A card raised just off the popover.
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                                .shadow(color: .black.opacity(0.10), radius: 3, y: 1.5)
                        }
                        .padding(.horizontal, -4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            Divider()
            AgendaListView()
            if hasProgress {
                Divider()
                VStack(spacing: 10) {
                    if preferences.showYearProgress {
                        let progress = YearProgress(date: appState.now, calendar: appState.calendar)
                        ProgressRow(title: "Year", fraction: progress.fraction, leading: progress.elapsedText, trailing: progress.remainingText)
                    }
                    if preferences.showDayProgress {
                        let progress = DayProgress(date: appState.now, calendar: appState.calendar)
                        ProgressRow(
                            title: "Day",
                            fraction: progress.fraction,
                            leading: "\(ProgressText.percent(progress.fraction)) of today",
                            trailing: "\(DurationText.string(progress.remaining)) left"
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }
}

private struct HeaderBar: View {

    @Environment(AppState.self) private var appState
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(appState.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .orbitFont(.title)
            Spacer()
            HStack(spacing: 0) {
                iconButton("plus", label: "New event", key: "n") { appState.beginNewEvent() }
                iconButton("magnifyingglass", label: "Search events", key: "f") { appState.beginSearch() }
                iconButton(
                    appState.preferences.showMonthGrid ? "chevron.up" : "chevron.down",
                    label: appState.preferences.showMonthGrid ? "Hide month" : "Show month",
                    key: "m"
                ) {
                    withAnimation(.snappy(duration: 0.2)) { appState.preferences.showMonthGrid.toggle() }
                }
                iconButton("gearshape", label: "Settings", key: ",", action: openSettings)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func iconButton(_ symbol: String, label: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(key, modifiers: .command)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A capsule bar with its labels inside. The labels are drawn twice, dark over the empty track and white
/// over the fill, so they stay readable wherever the fill ends, even partway through a word.
private struct ProgressRow: View {

    @Environment(\.textScale) private var scale
    let title: String
    let fraction: Double
    let leading: String
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .orbitFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            bar
        }
    }

    private var bar: some View {
        let clamped = min(max(fraction, 0), 1)
        return Capsule()
            .fill(.quaternary)
            .overlay { labels.foregroundStyle(.secondary) }
            .overlay {
                GeometryReader { geometry in
                    let fillWidth = geometry.size.width * clamped
                    ZStack {
                        Capsule().fill(Color.orbitTeal)
                        labels.foregroundStyle(.white)
                    }
                    // Clipping a full-width capsule keeps the left end round even when the fill is a sliver.
                    .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
                }
            }
            .frame(height: 18 * scale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(leading), \(trailing)")
            .accessibilityValue(Text(clamped, format: .percent))
    }

    private var labels: some View {
        HStack(spacing: 6) {
            Text(leading)
                .orbitFont(.caption, weight: .bold, monospacedDigit: true)
            Spacer(minLength: 0)
            Text(trailing)
                .orbitFont(.caption, monospacedDigit: true)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 8 * scale)
    }
}

private struct MonthHeaderView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Text(appState.displayedMonth, format: .dateTime.month(.wide).year())
                .orbitFont(.headline)
            Spacer()
            HStack(spacing: 2) {
                navButton("chevron.left", label: "Previous month") { appState.showMonth(offset: -1) }
                navButton("smallcircle.filled.circle", label: "Today") { appState.showToday() }
                navButton("chevron.right", label: "Next month") { appState.showMonth(offset: 1) }
            }
        }
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct AccessRequiredView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Orbit needs calendar access")
                .orbitFont(.headline)
            Text("Allow access to see your events here and in the menu bar.")
                .orbitFont(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if appState.access == .notDetermined {
                Button("Allow access") { Task { await appState.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
