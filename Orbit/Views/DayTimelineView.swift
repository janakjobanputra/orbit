import SwiftUI

/// The selected day as an hour-by-hour timeline, like Calendar's day view, or a few days side by side.
/// All-day events sit above it; it opens scrolled to the current hour (or the first event on other days).
struct DayTimelineView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.textScale) private var scale

    /// Leaves room above the first hour's label, which sits half above its line.
    private static let scrollAnchor = UnitPoint(x: 0.5, y: 0.04)

    private var hourHeight: CGFloat { appState.preferences.eventDensity.hourHeight * scale }
    private var gutter: CGFloat { 46 * scale }
    /// Space kept clear on the right of the timeline.
    private let trailing: CGFloat = 10

    var body: some View {
        let columns = appState.dayColumns
        VStack(alignment: .leading, spacing: 0) {
            if columns.count == 1, let day = columns.first {
                singleDayHeader(day)
            } else {
                multiDayHeader(columns)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourLines
                        GeometryReader { geometry in
                            let dayWidth = (geometry.size.width - gutter - trailing) / CGFloat(max(columns.count, 1))
                            ForEach(Array(columns.enumerated()), id: \.element.id) { index, day in
                                let left = gutter + CGFloat(index) * dayWidth
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 0.5, height: 24 * hourHeight)
                                        .offset(x: left - 1)
                                }
                                ForEach(day.timeline.blocks) { block in
                                    let columnWidth = dayWidth / CGFloat(block.columns)
                                    TimelineBlock(event: block.event, height: height(of: block), isNarrow: columnWidth < 110)
                                        .frame(width: columnWidth - 2, height: height(of: block))
                                        .offset(x: left + CGFloat(block.column) * columnWidth, y: y(minute: block.startMinute) + 1)
                                }
                                if columns.count > 1, isToday(day.date) {
                                    NowMarker()
                                        .frame(width: dayWidth)
                                        .offset(x: left - 3, y: y(minute: minutesIntoDay(appState.now)) - 3)
                                }
                            }
                        }
                        if columns.count == 1, let day = columns.first, isToday(day.date) {
                            NowMarker()
                                .padding(.leading, gutter - 4)
                                .padding(.trailing, 8)
                                .offset(y: y(minute: minutesIntoDay(appState.now)) - 3)
                        }
                    }
                    .frame(height: 24 * hourHeight)
                    .padding(.vertical, 8)
                }
                .onAppear { proxy.scrollTo(openingHour(columns), anchor: Self.scrollAnchor) }
                .onChange(of: appState.calendar.startOfDay(for: appState.selectedDate)) {
                    proxy.scrollTo(openingHour(appState.dayColumns), anchor: Self.scrollAnchor)
                }
            }
            .frame(height: 300 * scale)
        }
    }

    private func singleDayHeader(_ day: DayColumn) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            title(for: day.date, short: false)
                .orbitFont(.subheadline, weight: .semibold)
                .foregroundStyle(isToday(day.date) ? Color.orbitTeal : Color.secondary)
                .padding(.bottom, day.timeline.allDay.isEmpty ? 0 : 2)
            ForEach(day.timeline.allDay) { event in
                EventRowView(event: event, isSingleLine: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    /// Each day's name over its column, with its all-day events under it.
    private func multiDayHeader(_ columns: [DayColumn]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(columns) { day in
                VStack(alignment: .leading, spacing: 3) {
                    title(for: day.date, short: true)
                        .orbitFont(.subheadline, weight: .semibold)
                        .foregroundStyle(isToday(day.date) ? Color.orbitTeal : Color.secondary)
                        .lineLimit(1)
                    ForEach(day.timeline.allDay) { event in
                        AllDayChip(event: event)
                    }
                }
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.trailing, trailing)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hourDate(hour), format: .dateTime.hour())
                        .orbitFont(.caption, monospacedDigit: true)
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 10, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func isToday(_ date: Date) -> Bool {
        appState.calendar.isDate(date, inSameDayAs: appState.now)
    }

    /// "Today", "Tomorrow", or the date: "Thursday, Nov 12" for one day, "Thu 12" over a narrow column.
    private func title(for date: Date, short: Bool) -> Text {
        let calendar = appState.calendar
        if isToday(date) { return Text("Today") }
        if !short, let tomorrow = calendar.date(byAdding: .day, value: 1, to: appState.now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return Text("Tomorrow")
        }
        return short
            ? Text(date, format: .dateTime.weekday(.abbreviated).day())
            : Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func hourDate(_ hour: Int) -> Date {
        let start = appState.calendar.startOfDay(for: appState.selectedDate)
        return appState.calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    private func minutesIntoDay(_ date: Date) -> Int {
        Int(date.timeIntervalSince(appState.calendar.startOfDay(for: date)) / 60)
    }

    private func y(minute: Int) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight
    }

    private func height(of block: DayTimeline.Block) -> CGFloat {
        max(y(minute: block.endMinute - block.startMinute) - 2, 12)
    }

    /// An hour before now when today is shown, else just before the earliest event, else 8 AM.
    private func openingHour(_ columns: [DayColumn]) -> Int {
        if columns.contains(where: { isToday($0.date) }) { return max(0, minutesIntoDay(appState.now) / 60 - 1) }
        if let first = columns.flatMap({ $0.timeline.blocks.map(\.startMinute) }).min() { return max(0, first / 60 - 1) }
        return 8
    }
}

/// An all-day event over a narrow day column.
private struct AllDayChip: View {

    let event: CalendarEvent

    var body: some View {
        Text(event.title)
            .orbitFont(.caption, weight: .medium)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(event.color.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            .opensDetails(of: event)
    }
}

private struct TimelineBlock: View {

    @Environment(AppState.self) private var appState
    @Environment(\.timeZone) private var timeZone
    let event: CalendarEvent
    let height: CGFloat
    /// Side by side with other days or events: the title keeps to one line rather than breaking mid-word,
    /// and only the start time shows.
    var isNarrow = false

    var body: some View {
        let isPast = event.end <= appState.now
        let attendance = event.attendance
        let shape = RoundedRectangle(cornerRadius: 5)
        HStack(spacing: 0) {
            AttendanceBar(color: event.color, attendance: attendance)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .strikethrough(attendance == .declined)
                    .orbitFont(.caption, weight: .semibold)
                    .lineLimit(height < 34 || isNarrow ? 1 : 2)
                if height >= 30 {
                    detailText
                        .orbitFont(.caption, monospacedDigit: true)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, height < 24 ? 1 : 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Unanswered invites are outlined rather than filled, and maybes get a lighter fill with a dashed edge.
        .background(event.color.color.opacity(fillOpacity(attendance)), in: shape)
        .overlay {
            switch attendance {
            case .notAnswered:
                shape.strokeBorder(event.color.color.opacity(0.8), lineWidth: 1)
            case .maybe:
                shape.strokeBorder(event.color.color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            case .attending, .declined:
                EmptyView()
            }
        }
        .clipShape(shape)
        .opacity(isPast || attendance == .declined ? 0.55 : 1)
        .opensDetails(of: event)
    }

    private var detailText: Text {
        let time = isNarrow
            ? Text(event.start, format: Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
            : Text(event.start..<event.end, format: .timeRange(in: timeZone))
        guard let label = event.attendance.label else { return time }
        return Text("\(time) · \(label)")
    }

    private func fillOpacity(_ attendance: Attendance) -> Double {
        switch attendance {
        case .attending: 0.18
        case .notAnswered: 0.04
        case .maybe: 0.09
        case .declined: 0.10
        }
    }
}

private struct NowMarker: View {

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(.red)
                .frame(height: 1.5)
        }
    }
}
