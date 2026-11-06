import SwiftUI

/// The scrolling page each Settings pane is drawn on.
/// A grouped Form underneath: unlike a hand-built ScrollView, it stays stable beside the preview inspector,
/// which otherwise sends the window into a layout loop that AppKit kills the app for.
struct SettingsPage<Content: View>: View {

    @ViewBuilder var content: Content
    /// Absent when a page is drawn on its own, as in tests.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    var body: some View {
        ScrollViewReader { proxy in
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                // A search result opened this page: scroll to its section, once the page has laid out.
                .task(id: navigation?.requestedSection) {
                    guard let section = navigation?.requestedSection else { return }
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    navigation?.requestedSection = nil
                }
        }
    }
}

/// A bold heading over a rounded card of rows, with a hairline between each row.
struct SettingsSection<Content: View, Accessory: View>: View {

    let title: String?
    var footer: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            content
        } header: {
            if title != nil || Accessory.self != EmptyView.self {
                HStack {
                    if let title {
                        Text(title)
                    }
                    Spacer()
                    accessory
                }
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(title)
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.accessory = EmptyView()
        self.content = content()
    }
}

/// One line of a section: the setting and what it does on the left, its control on the right.
///
/// These all use the Form's own row layout rather than an HStack. AppKit-backed controls (switches, pickers) in a
/// hand-built row keep changing the split view column's minimum size beside the preview inspector, a layout loop
/// that AppKit kills the app for.
struct SettingsRow<Control: View>: View {

    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            SettingsLabel(title: title, detail: detail)
        }
    }
}

private struct SettingsLabel: View {

    let title: String
    let detail: String?

    var body: some View {
        Text(title)
        if let detail {
            Text(detail)
        }
    }
}

/// A setting that's on or off, as a switch in Orbit's teal.
struct SettingsToggle: View {

    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsLabel(title: title, detail: detail)
        }
        .toggleStyle(.switch)
    }
}

/// A choice from a dropdown.
struct SettingsMenuPicker<Value: Hashable, Options: View>: View {

    let title: String
    var detail: String?
    @Binding var selection: Value
    @ViewBuilder var options: Options

    var body: some View {
        Picker(selection: $selection) {
            options
        } label: {
            SettingsLabel(title: title, detail: detail)
        }
    }
}

/// A choice from a few short options, all visible at once.
struct SettingsSegmentedPicker<Value: Hashable, Options: View>: View {

    let title: String
    var detail: String?
    @Binding var selection: Value
    @ViewBuilder var options: Options

    var body: some View {
        Picker(selection: $selection) {
            options
        } label: {
            SettingsLabel(title: title, detail: detail)
        }
        .pickerStyle(.segmented)
    }
}

/// A question that opens to show its answer. The whole row toggles, not just the chevron.
struct SettingsDisclosureRow<Answer: View>: View {

    let question: String
    @Binding var isExpanded: Bool
    @ViewBuilder var answer: Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(question)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                answer
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sidebar

/// The search field at the top of the sidebar. ⌘F focuses it and Esc clears it.
private struct SettingsSearchField: View {

    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    query = ""
                    isFocused = false
                }
            if !query.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 9, style: .continuous))
        .background {
            Button("Search Settings") { isFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// The sidebar's pages: everyday settings, then the ones that look after Orbit itself, then About on its own.
struct SettingsSidebar: View {

    let navigation: SettingsNavigation

    /// While search results show, no page is selected, and clicking any row ends the search.
    private var selection: SettingsPane? { navigation.isSearching ? nil : navigation.pane }

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            SettingsSearchField(query: $navigation.query)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 14)
            pages
        }
    }

    private var pages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { index, group in
                    if let heading = group.heading {
                        Text(heading.uppercased())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    } else if index > 0 {
                        Spacer().frame(height: 18)
                    }
                    ForEach(group.panes) { pane in
                        row(pane)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
    }

    private func row(_ pane: SettingsPane) -> some View {
        let isSelected = pane == selection
        return Button {
            navigation.open(pane)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.orbitTeal : .secondary)
                    .frame(width: 22)
                Text(pane.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.orbitTeal.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.orbitTeal.opacity(0.45), lineWidth: 2)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func move(by offset: Int) -> KeyPress.Result {
        let panes = SettingsPane.groups.flatMap(\.panes)
        guard let index = panes.firstIndex(of: navigation.pane), panes.indices.contains(index + offset) else { return .ignored }
        navigation.open(panes[index + offset])
        return .handled
    }
}
