import SwiftUI

/// Searches events from the past three months and the coming year.
struct SearchView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search events", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        if let first = appState.searchResults.first { appState.show(date: first.start) }
                    }
                Button("Done") { appState.returnToAgenda() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            results
        }
        .onAppear { isFieldFocused = true }
    }

    @ViewBuilder
    private var results: some View {
        let matches = appState.searchResults
        if appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            message("Search titles and locations from the past 3 months and the next year.")
        } else if matches.isEmpty {
            message("No matching events")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(matches.prefix(50)) { event in
                        Button {
                            appState.show(date: event.start)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                                    .orbitFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                EventRowView(event: event)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SearchResultButtonStyle())
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .orbitFont(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(20)
    }
}

private struct SearchResultButtonStyle: ButtonStyle {

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : isHovered ? 0.05 : 0))
            )
            .onHover { isHovered = $0 }
    }
}
