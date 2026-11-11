import AppKit
import SwiftUI

/// Everything about one event, shown in a popover beside the calendar when its row is clicked.
struct EventDetailView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.timeZone) private var timeZone
    @Environment(\.textScale) private var scale
    let event: CalendarEvent

    @State private var isConfirmingDelete = false
    @State private var didCopy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Divider()
                    details
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 480 * scale)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 300 * scale)
        .tint(.orbitTeal)
        .background {
            Button("Close") { appState.detailEventID = nil }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .confirmationDialog("Delete “\(event.title)”?", isPresented: $isConfirmingDelete) {
            Button("Delete Event", role: .destructive, action: delete)
        } message: {
            Text(event.calendarItemID != nil ? "Only this occurrence is deleted." : "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ColorBar(color: event.color)
                    .frame(height: 20 * scale)
                Text(event.title)
                    .orbitFont(.title)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let label = pillText {
                    TimingPill(text: label)
                }
            }
            if let info = appState.calendarInfo(for: event) {
                HStack(spacing: 5) {
                    Circle().fill(info.color.color).frame(width: 6, height: 6)
                    Text(info.sourceTitle.isEmpty ? info.title : "\(info.title) · \(info.sourceTitle)")
                        .lineLimit(1)
                }
                .orbitFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
            whenText
                .orbitFont(.callout, monospacedDigit: true)
                .foregroundStyle(.secondary)
        }
    }

    private var pillText: String? {
        switch EventTiming(event: event, now: appState.now) {
        case .now: "Now"
        case .soon(let interval): EventTiming.soon(startsIn: interval).label
        case .ended: "Ended"
        case .later: nil
        }
    }

    private var whenText: Text {
        let day = Text(event.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if event.isAllDay {
            return Text("\(day) · All day")
        }
        let duration = DurationText.string(event.end.timeIntervalSince(event.start))
        if appState.calendar.isDate(event.start, inSameDayAs: event.end) {
            let times = Text(event.start..<event.end, format: .timeRange(in: timeZone))
            return Text("\(day) · \(times) · \(duration)")
        }
        let range = Date.IntervalFormatStyle(date: .abbreviated, time: .shortened, timeZone: timeZone)
        return Text("\(Text(event.start..<event.end, format: range)) · \(duration)")
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        if let url = event.meetingURL {
            Button { appState.openMeeting(url) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 15 * scale))
                        .foregroundStyle(Color.orbitTeal)
                        .frame(width: 30 * scale, height: 30 * scale)
                        .background(Color.orbitTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Join").orbitFont(.callout, weight: .semibold)
                        Text(LinkText.host(url)).orbitFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(url.absoluteString)
        }

        if let location = event.location, !location.isEmpty {
            DetailRow(symbol: "mappin.and.ellipse") {
                Button { appState.openInMaps(location) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(location).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Text(appState.preferences.mapsProvider.label)
                            .orbitFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        ForEach(event.links, id: \.self) { url in
            DetailRow(symbol: "link") {
                Link(destination: url) {
                    Text(LinkText.host(url) + url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.orbitTeal)
                .help(url.absoluteString)
            }
        }

        if let summary = GuestSummary.text(event.guests) {
            DetailRow(symbol: "person.2") {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(event.guests, id: \.self) { guest in
                            GuestRow(guest: guest)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text(summary)
                }
            }
        }

        if let notes = event.notes {
            DetailRow(symbol: "note.text") {
                Text(NotesLinks.attributed(notes))
                    .orbitFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .orbitFont(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                appState.openInCalendar(event)
            } label: {
                Label("Open in Calendar", systemImage: "calendar")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(EventCopyText.make(event, calendar: appState.calendar), forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(width: 16)
            }
            .help(didCopy ? "Copied" : "Copy details")
            .accessibilityLabel(didCopy ? "Copied" : "Copy details")
            Spacer()
            if appState.canDelete(event) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)
                .help("Delete event")
                .accessibilityLabel("Delete event")
            }
        }
        .controlSize(.small)
    }

    private func delete() {
        do {
            try appState.deleteEvent(event)
            appState.detailEventID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DetailRow<Content: View>: View {

    @Environment(\.textScale) private var scale
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16 * scale)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .orbitFont(.callout)
    }
}

private struct GuestRow: View {

    let guest: Guest

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(guest.name)
                .lineLimit(1)
            if guest.isOrganizer {
                Text("organizer").foregroundStyle(.tertiary)
            } else if guest.isYou {
                Text("you").foregroundStyle(.tertiary)
            }
        }
        .orbitFont(.caption)
    }

    private var symbol: String {
        switch guest.response {
        case .accepted: "checkmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .pending: "circle.dashed"
        }
    }

    private var color: Color {
        switch guest.response {
        case .accepted: .green
        case .tentative: .orange
        case .declined: .red
        case .pending: .secondary
        }
    }
}

enum NotesLinks {

    /// Notes with each web address turned into a clickable link.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].link = url
            result[start..<end].foregroundColor = .orbitTeal
        }
        return result
    }
}
