import SwiftUI

/// Day-by-day list of events from the selected day onwards. Each day's title and all-day events stay pinned
/// to the top while that day's timed events scroll under them, until the next day's header pushes them off.
struct AgendaListView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.textScale) private var scale

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(appState.agendaDays) { day in
                    AgendaSection(day: day)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 340 * scale)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AgendaSection: View {

    @Environment(AppState.self) private var appState
    let day: AgendaDay

    var body: some View {
        let spacing = appState.preferences.eventDensity.eventSpacing
        let rows = appState.agendaRows(for: day)
        let allDay = rows.filter(\.isAllDay)
        let timed = rows.filter { !$0.isAllDay }
        Section {
            VStack(alignment: .leading, spacing: spacing) {
                if day.hasNothingLeft(now: appState.now) {
                    ForEach(timed) { row in
                        if case .event(let event) = row { EventRowView(event: event) }
                    }
                    placeholder("No events left today")
                } else if day.events.isEmpty && !rows.contains(where: { if case .free = $0 { true } else { false } }) {
                    placeholder("No events")
                } else {
                    ForEach(timed) { row in
                        switch row {
                        case .event(let event): EventRowView(event: event)
                        case .free(let gap): FreeTimeRow(gap: gap)
                        case .now: NowLine()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, timed.isEmpty ? 0 : spacing)
            .padding(.bottom, appState.preferences.eventDensity.sectionSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            VStack(alignment: .leading, spacing: 3) {
                title
                    .orbitFont(.subheadline, weight: .semibold)
                    .foregroundStyle(day.kind == .today ? Color.orbitTeal : Color.secondary)
                    .padding(.bottom, allDay.isEmpty ? 0 : 2)
                ForEach(allDay) { row in
                    if case .event(let event) = row {
                        EventRowView(event: event, isSingleLine: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, allDay.isEmpty ? 4 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opaque, so timed events scrolling underneath don't show through.
            .background(Color.orbitPopoverBackground)
            .overlay(alignment: .bottom) {
                if !allDay.isEmpty {
                    Divider()
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .orbitFont(.callout)
            .foregroundStyle(.tertiary)
    }

    // Text(_:format:) formats in the environment's time zone, like the rest of the popover.
    private var title: Text {
        switch day.kind {
        case .today: Text("Today")
        case .tomorrow: Text("Tomorrow")
        case .other: Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
}

private struct NowLine: View {

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(.red.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.vertical, 1)
        .accessibilityLabel("Now")
    }
}

private struct FreeTimeRow: View {

    @Environment(\.timeZone) private var timeZone

    let gap: FreeGap

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free · \(DurationText.string(gap.duration))")
                    .orbitFont(.callout)
                    .foregroundStyle(.secondary)
                Text(gap.start..<gap.end, format: .timeRange(in: timeZone))
                    .orbitFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EventRowView: View {

    @Environment(\.timeZone) private var timeZone
    @Environment(\.textScale) private var scale
    @Environment(AppState.self) private var appState
    let event: CalendarEvent
    /// One line with no time, for all-day events in a day's pinned header.
    var isSingleLine = false

    var body: some View {
        let isHighlighted = EventTiming.isHighlighted(event, now: appState.now)
        Group {
            if isSingleLine {
                singleLineRow
            } else if isHighlighted {
                highlightedRow
            } else {
                compactRow
            }
        }
        .opensDetails(of: event)
    }

    private var singleLineRow: some View {
        HStack(spacing: 7) {
            AttendanceBar(color: event.color, attendance: event.attendance)
                .frame(width: 3, height: 13 * scale)
            titleText
                .orbitFont(.callout, weight: .medium)
                .lineLimit(1)
            if let label = event.attendance.label {
                Text(label)
                    .orbitFont(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(event.attendance == .declined ? 0.5 : 1)
    }

    /// The usual one- or two-line row.
    private var compactRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ColorBar(color: event.color, attendance: event.attendance)
            VStack(alignment: .leading, spacing: 2) {
                titleText
                    .orbitFont(.callout, weight: .medium)
                    .lineLimit(2)
                timeAndAttendance
                    .orbitFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                if let location = event.location, !location.isEmpty, event.meetingURL == nil {
                    Button {
                        appState.openInMaps(location)
                    } label: {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .orbitFont(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Open in \(appState.preferences.mapsProvider.label)")
                }
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL, event.end > appState.now {
                Button("Join") { appState.openMeeting(url) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(event.end < appState.now || event.attendance == .declined ? 0.5 : 1)
    }

    /// The event happening now, or starting within ten minutes: tinted, with its links one click away.
    private var highlightedRow: some View {
        let timing = EventTiming(event: event, now: appState.now)
        return HStack(alignment: .top, spacing: 8) {
            ColorBar(color: event.color, attendance: event.attendance)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    timeAndAttendance
                        .orbitFont(.caption, monospacedDigit: true)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let label = timing.label {
                        TimingPill(text: label)
                    }
                }
                titleText
                    .orbitFont(.body, weight: .semibold)
                    .lineLimit(2)
                let chips = linkChips
                if !chips.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(chips) { chip in
                            LinkChip(chip: chip)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8 * scale)
        .background {
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .fill(Color.orbitTeal.opacity(0.10))
                .strokeBorder(Color.orbitTeal.opacity(0.35), lineWidth: 0.5)
        }
    }

    private var linkChips: [LinkChip.Model] {
        var chips: [LinkChip.Model] = []
        if let url = event.meetingURL {
            chips.append(.init(id: "join", title: "Join", symbol: "video.fill", isProminent: true) { appState.openMeeting(url) })
        }
        if let location = event.location, !location.isEmpty {
            chips.append(.init(id: "map", title: "Map", symbol: "mappin.and.ellipse") { appState.openInMaps(location) })
        }
        for url in event.links.prefix(2) {
            chips.append(.init(id: url.absoluteString, title: LinkText.host(url), symbol: "link") { NSWorkspace.shared.open(url) })
        }
        return chips
    }

    private var timeText: Text {
        if event.isAllDay { return Text("All day") }
        return Text(event.start..<max(event.end, event.start), format: .timeRange(in: timeZone))
    }

    /// The time, followed by "Not answered", "Maybe" or "Declined" for invitations you haven't accepted.
    private var timeAndAttendance: Text {
        guard let label = event.attendance.label else { return timeText }
        return Text("\(timeText) · \(label)")
    }

    /// Declined events are crossed out.
    private var titleText: Text {
        Text(event.title).strikethrough(event.attendance == .declined)
    }
}

struct ColorBar: View {

    let color: EventColor
    var attendance: Attendance = .attending

    var body: some View {
        AttendanceBar(color: color, attendance: attendance)
            .frame(width: 3)
    }
}

/// The calendar-coloured bar beside an event: solid when you're going, an outline when you haven't
/// answered, half-strength for maybe, and faint once declined.
struct AttendanceBar: View {

    let color: EventColor
    let attendance: Attendance

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5)
        switch attendance {
        case .attending: shape.fill(color.color)
        case .notAnswered: shape.strokeBorder(color.color, lineWidth: 1)
        case .maybe: shape.fill(color.color.opacity(0.45))
        case .declined: shape.fill(color.color.opacity(0.3))
        }
    }
}

/// "in 6m" or "28m left".
struct TimingPill: View {

    let text: String

    var body: some View {
        Text(text)
            .orbitFont(.caption, weight: .semibold, monospacedDigit: true)
            .foregroundStyle(Color.orbitTeal)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.orbitTeal.opacity(0.15), in: Capsule())
    }
}

struct LinkChip: View {

    struct Model: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var isProminent = false
        let action: () -> Void
    }

    let chip: Model

    var body: some View {
        Button(action: chip.action) {
            Label(chip.title, systemImage: chip.symbol)
                .lineLimit(1)
                .orbitFont(.caption, weight: .medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(chip.isProminent ? Color.white : Color.primary)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                    if chip.isProminent {
                        shape.fill(Color.orbitTeal)
                    } else {
                        shape.fill(.background.opacity(0.6)).strokeBorder(.separator, lineWidth: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(chip.title)
    }
}

/// Lays children out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {

    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows.removeLast()
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            row.indices.append(index)
            row.xs.append(x)
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows.append(row)
        }
        return rows
    }
}

enum LinkText {

    /// "docs.google.com" for a link's chip.
    static func host(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension FormatStyle where Self == Date.IntervalFormatStyle {
    /// "9:00 – 11:00 AM". Interval styles don't pick up the view's time zone on their own.
    static func timeRange(in timeZone: TimeZone) -> Self {
        Date.IntervalFormatStyle(timeZone: timeZone).hour().minute()
    }
}

/// Clicking the view opens the event's details in a popover beside it.
private struct EventDetailsOnClick: ViewModifier {

    @Environment(AppState.self) private var appState
    @Environment(\.timeZone) private var timeZone
    @Environment(\.textScale) private var scale
    let event: CalendarEvent

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { appState.detailEventID = event.id }
            .popover(isPresented: isShowingDetails, arrowEdge: .leading) {
                EventDetailView(event: event)
                    .environment(appState)
                    .environment(\.timeZone, timeZone)
                    .environment(\.textScale, scale)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows details")
    }

    /// Kept in AppState so Escape can close the detail before the popover, and opening another event swaps it.
    private var isShowingDetails: Binding<Bool> {
        Binding(
            get: { appState.detailEventID == event.id },
            set: { isShown in
                if !isShown, appState.detailEventID == event.id { appState.detailEventID = nil }
            }
        )
    }
}

extension View {
    func opensDetails(of event: CalendarEvent) -> some View {
        modifier(EventDetailsOnClick(event: event))
    }
}
