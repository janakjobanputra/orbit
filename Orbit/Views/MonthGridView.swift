import SwiftUI

struct MonthGridView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.textScale) private var scale

    var body: some View {
        let preferences = appState.preferences
        let days = appState.gridDays
        let spacing = preferences.calendarDensity.gridSpacing * scale

        // A plain Grid rather than a lazy one: it's at most 42 cells, and a lazy grid keeps the previous
        // month's row heights for a moment after switching between five- and six-week months.
        Grid(horizontalSpacing: 0, verticalSpacing: spacing) {
            GridRow {
                if preferences.showWeekNumbers {
                    headerText("Wk")
                }
                ForEach(Array(MonthGrid.weekdaySymbols(calendar: appState.calendar).enumerated()), id: \.offset) { _, symbol in
                    headerText(symbol)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<(days.count / 7), id: \.self) { week in
                let weekDays = days[(week * 7)..<(week * 7 + 7)]
                GridRow(alignment: .top) {
                    if preferences.showWeekNumbers, let first = weekDays.first {
                        // Same height and inset as a day's number, so the two line up.
                        Text("\(appState.calendar.component(.weekOfYear, from: first.date))")
                            .orbitFont(.caption, monospacedDigit: true)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: preferences.calendarDensity.dayCellSize * scale)
                            .padding(.vertical, 2)
                    }
                    ForEach(weekDays) { day in
                        DayCell(day: day)
                    }
                }
            }
        }
    }

    private func headerText(_ text: String) -> some View {
        Text(text)
            .orbitFont(.caption, weight: .medium)
            .foregroundStyle(.secondary)
            .frame(height: 18 * scale)
    }
}

private struct DayCell: View {

    @Environment(AppState.self) private var appState
    @Environment(\.textScale) private var scale
    let day: CalendarDay

    private var isToday: Bool { appState.calendar.isDate(day.date, inSameDayAs: appState.now) }
    private var isSelected: Bool { appState.calendar.isDate(day.date, inSameDayAs: appState.selectedDate) }
    private var isTodayHighlighted: Bool { isToday && appState.preferences.highlightToday }

    var body: some View {
        let size = appState.preferences.calendarDensity.dayCellSize * scale
        Button {
            appState.selectedDate = day.date
        } label: {
            VStack(spacing: 2) {
                Text(day.date, format: .dateTime.day())
                    .orbitFont(.callout, weight: isToday ? .semibold : .regular, monospacedDigit: true)
                    .foregroundStyle(foreground)
                    .frame(width: size, height: size)
                    .background {
                        if isTodayHighlighted {
                            Circle().fill(Color.orbitTeal)
                        } else if isSelected {
                            Circle().strokeBorder(Color.orbitTeal, lineWidth: 1.5)
                        }
                    }
                dots
                    .frame(height: 4)
                    .opacity(day.isInDisplayedMonth ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide)))
    }

    @ViewBuilder
    private var dots: some View {
        switch appState.preferences.eventDots {
        case .off:
            EmptyView()
        case .single:
            if !appState.events(on: day.date).isEmpty {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
            }
        case .colors:
            HStack(spacing: 2) {
                ForEach(appState.eventColors(on: day.date), id: \.self) { color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    private var foreground: Color {
        if isTodayHighlighted { return .white }
        guard day.isInDisplayedMonth else { return .secondary.opacity(0.6) }
        if isToday { return .orbitTeal }
        if appState.preferences.dimWeekends && appState.calendar.isDateInWeekend(day.date) { return .secondary }
        return .primary
    }
}
