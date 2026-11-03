import SwiftUI

/// Inline form for adding an event to a writable calendar.
struct NewEventView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var isTitleFocused: Bool

    @State private var title = ""
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var calendarID = ""
    @State private var location = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var hasLoadedDefaults = false

    private var isLinkInvalid: Bool {
        NewEventDraft.optional(link) != nil && NewEventDraft.link(from: link) == nil
    }

    private var canSave: Bool {
        !calendarID.isEmpty && !isLinkInvalid && NewEventDraft.isValid(title: title, start: start, end: end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Event title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit(save)

            Toggle("All day", isOn: $isAllDay)
                .toggleStyle(.switch)
                .controlSize(.small)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Starts").foregroundStyle(.secondary)
                    DatePicker("Starts", selection: $start, displayedComponents: components)
                        .labelsHidden()
                }
                GridRow {
                    Text("Ends").foregroundStyle(.secondary)
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: components)
                        .labelsHidden()
                }
                GridRow {
                    Text("Calendar").foregroundStyle(.secondary)
                    Picker("Calendar", selection: $calendarID) {
                        ForEach(appState.writableCalendars) { info in
                            Text(info.title).tag(info.id)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Location").foregroundStyle(.secondary)
                    TextField("Location", text: $location, prompt: Text("Add location"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Link").foregroundStyle(.secondary)
                    TextField("Link", text: $link, prompt: Text("Video call or web link"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                }
                GridRow(alignment: .top) {
                    Text("Notes").foregroundStyle(.secondary)
                        .padding(.top, 3)
                    TextField("Notes", text: $notes, prompt: Text("Add notes"), axis: .vertical)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }
            }
            .font(.callout)

            if isLinkInvalid {
                Text("The link needs to be a web address, like zoom.us/j/123.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { appState.returnToAgenda() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Event", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(14)
        .onAppear(perform: loadDefaults)
        .onChange(of: start) { oldValue, newValue in
            end = end.addingTimeInterval(newValue.timeIntervalSince(oldValue))
        }
    }

    private var components: DatePickerComponents {
        isAllDay ? .date : [.date, .hourAndMinute]
    }

    private func loadDefaults() {
        guard !hasLoadedDefaults else { return }
        hasLoadedDefaults = true
        start = NewEventDraft.defaultStart(on: appState.selectedDate, now: appState.now, calendar: appState.calendar)
        end = start.addingTimeInterval(NewEventDraft.defaultDuration)
        let writable = appState.writableCalendars.map(\.id)
        calendarID = appState.defaultCalendarID.flatMap { writable.contains($0) ? $0 : nil } ?? writable.first ?? ""
        isTitleFocused = true
    }

    private func save() {
        guard canSave else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventStart = isAllDay ? appState.calendar.startOfDay(for: start) : start
        let eventEnd = isAllDay ? appState.calendar.startOfDay(for: end) : end
        do {
            try appState.createEvent(
                title: trimmed, start: eventStart, end: eventEnd, isAllDay: isAllDay, calendarID: calendarID,
                location: NewEventDraft.optional(location),
                url: NewEventDraft.link(from: link),
                notes: NewEventDraft.optional(notes)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
