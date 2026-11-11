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
                            .padding(.top, MonthLabel.inset(preferences.calendarSpan, scale: scale))
                            .padding(.vertical, 2)
                    }
                    ForEach(weekDays) { day in
                        // Only where a new month starts partway through: the header already names the first one.
                        DayCell(day: day, startsNewMonth: day.id != days.first?.id && appState.calendar.component(.day, from: day.date) == 1)
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
    var startsNewMonth = false

    private var isToday: Bool { appState.calendar.isDate(day.date, inSameDayAs: appState.now) }
    private var isSelected: Bool { appState.calendar.isDate(day.date, inSameDayAs: appState.selectedDate) }
    private var isTodayHighlighted: Bool { isToday && appState.preferences.highlightToday }

    var body: some View {
        let size = appState.preferences.calendarDensity.dayCellSize * scale
        Button {
            appState.selectedDate = day.date
        } label: {
            VStack(spacing: 2) {
                if appState.preferences.calendarSpan == .threeWeeks {
                    MonthLabel(date: day.date, isShown: startsNewMonth)
                }
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

/// The 3-week view can run across months, so a 1st partway through carries a small "Dec" above it.
/// Every day keeps the space, so the rows stay level and the grid doesn't change height as you page.
private struct MonthLabel: View {

    @Environment(\.textScale) private var scale
    let date: Date
    let isShown: Bool

    private static let height: CGFloat = 11

    /// How far the label and its spacing push the day number down, for the week numbers to match.
    static func inset(_ span: CalendarSpan, scale: CGFloat) -> CGFloat {
        span == .threeWeeks ? height * scale + 2 : 0
    }

    var body: some View {
        Text(date, format: .dateTime.month(.abbreviated))
            .orbitFont(.caption, weight: .semibold)
            .foregroundStyle(Color.orbitTeal)
            .lineLimit(1)
            .fixedSize()
            .opacity(isShown ? 1 : 0)
            .accessibilityHidden(true)
            .frame(height: Self.height * scale)
    }
}
