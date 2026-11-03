import SwiftUI

/// The selected day as an hour-by-hour timeline, like Calendar's day view. All-day events sit above it;
/// it opens scrolled to the current hour (or the first event on other days).
struct DayTimelineView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.textScale) private var scale

    /// Leaves room above the first hour's label, which sits half above its line.
    private static let scrollAnchor = UnitPoint(x: 0.5, y: 0.04)

    private var hourHeight: CGFloat { 40 * scale }
    private var gutter: CGFloat { 46 * scale }

    var body: some View {
        let timeline = appState.dayTimeline
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                title
                    .orbitFont(.subheadline, weight: .semibold)
                    .foregroundStyle(isToday ? Color.orbitTeal : Color.secondary)
                    .padding(.bottom, timeline.allDay.isEmpty ? 0 : 2)
                ForEach(timeline.allDay) { event in
                    EventRowView(event: event, isSingleLine: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 7)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourLines
                        GeometryReader { geometry in
                            let width = geometry.size.width - gutter - 10
                            ForEach(timeline.blocks) { block in
                                let columnWidth = width / CGFloat(block.columns)
                                TimelineBlock(event: block.event, height: height(of: block))
                                    .frame(width: columnWidth - 2, height: height(of: block))
                                    .offset(x: gutter + CGFloat(block.column) * columnWidth, y: y(minute: block.startMinute) + 1)
                            }
                        }
                        if isToday {
                            NowMarker()
                                .padding(.leading, gutter - 4)
                                .padding(.trailing, 8)
                                .offset(y: y(minute: minutesIntoDay(appState.now)) - 3)
                        }
                    }
                    .frame(height: 24 * hourHeight)
                    .padding(.vertical, 8)
                }
                .onAppear { proxy.scrollTo(openingHour(timeline), anchor: Self.scrollAnchor) }
                .onChange(of: appState.calendar.startOfDay(for: appState.selectedDate)) {
                    proxy.scrollTo(openingHour(appState.dayTimeline), anchor: Self.scrollAnchor)
                }
            }
            .frame(height: 300 * scale)
        }
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

    private var isToday: Bool {
        appState.calendar.isDate(appState.selectedDate, inSameDayAs: appState.now)
    }

    private var title: Text {
        let calendar = appState.calendar
        if isToday { return Text("Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: appState.now),
           calendar.isDate(appState.selectedDate, inSameDayAs: tomorrow) {
            return Text("Tomorrow")
        }
        return Text(appState.selectedDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
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

    /// An hour before now on today, else just before the first event, else 8 AM.
    private func openingHour(_ timeline: DayTimeline) -> Int {
        if isToday { return max(0, minutesIntoDay(appState.now) / 60 - 1) }
        if let first = timeline.blocks.map(\.startMinute).min() { return max(0, first / 60 - 1) }
        return 8
    }
}

private struct TimelineBlock: View {

    @Environment(AppState.self) private var appState
    @Environment(\.timeZone) private var timeZone
    let event: CalendarEvent
    let height: CGFloat

    var body: some View {
        let isPast = event.end <= appState.now
        HStack(spacing: 0) {
            Rectangle()
                .fill(event.color.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .orbitFont(.caption, weight: .semibold)
                    .lineLimit(height < 34 ? 1 : 2)
                if height >= 30 {
                    Text(event.start..<event.end, format: .timeRange(in: timeZone))
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
        .background(event.color.color.opacity(0.18))
        .clipShape(.rect(cornerRadius: 5))
        .opacity(isPast ? 0.55 : 1)
        .opensDetails(of: event)
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
