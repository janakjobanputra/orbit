import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, display, calendars, notifications, backup, help, about

    var id: Self { self }

    /// How the sidebar lists them.
    static let groups: [(heading: String?, panes: [SettingsPane])] = [
        (nil, [.general, .display, .calendars, .notifications]),
        ("Manage", [.backup, .help]),
        (nil, [.about]),
    ]

    var title: String {
        switch self {
        case .general: "General"
        case .display: "Display"
        case .calendars: "Calendars"
        case .notifications: "Notifications"
        case .backup: "Backup"
        case .help: "Help"
        case .about: "About"
        }
    }

    /// Under the title in the window's toolbar.
    var subtitle: String {
        switch self {
        case .general: "Startup, theme and shortcuts"
        case .display: "Menu bar, calendar and layout"
        case .calendars: "What shows, and where new events go"
        case .notifications: "Alerts before your meetings"
        case .backup: "Export and import your settings"
        case .help: "Answers to common questions"
        case .about: "Version and updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .display: "menubar.rectangle"
        case .calendars: "calendar"
        case .notifications: "bell"
        case .backup: "arrow.up.arrow.down.circle"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

/// Sidebar, sections of settings, and a live preview in the inspector.
struct SettingsView: View {

    @AppStorage("settingsPane") private var savedPane: SettingsPane = .general
    /// Only the starting page comes from storage. A `-settingsPane` launch argument overrides UserDefaults for
    /// the whole run, so reading the page straight from storage would pin it there.
    @State private var navigation = SettingsNavigation(
        pane: UserDefaults.standard.string(forKey: "settingsPane").flatMap(SettingsPane.init(rawValue:)) ?? .general
    )

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(navigation: navigation)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            // The page changes inside one steady view. Hung on the page itself, these modifiers would apply to each
            // page separately, and the preview would be rebuilt, visibly, every time you changed page.
            SettingsPageContent(navigation: navigation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(navigation.pane.title)
                .toolbar(removing: .title)
                .toolbar { SettingsToolbar(navigation: navigation) }
                .inspector(isPresented: .constant(true)) {
                    SettingsPreview()
                        .interactiveDismissDisabled()
                }
        }
        .environment(navigation)
        .onChange(of: navigation.pane) { _, pane in savedPane = pane }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 700, idealHeight: 860)
        .tint(.orbitTeal)
    }
}

/// The open page, or search results while there's a search. Swaps instantly rather than animating.
private struct SettingsPageContent: View {

    let navigation: SettingsNavigation

    var body: some View {
        Group {
            if navigation.isSearching {
                SettingsSearchResults()
            } else {
                switch navigation.pane {
                case .general: GeneralSettingsTab()
                case .display: DisplaySettingsTab()
                case .calendars: CalendarsSettingsTab()
                case .notifications: NotificationsSettingsTab()
                case .backup: BackupSettingsTab()
                case .help: HelpSettingsTab()
                case .about: AboutSettingsTab()
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

/// Back and forward, then the page's title with its subtitle underneath.
private struct SettingsToolbar: ToolbarContent {

    let navigation: SettingsNavigation

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") { navigation.goBack() }
                .keyboardShortcut("[")
                .disabled(!navigation.canGoBack)
                .help("Back")
            Button("Forward", systemImage: "chevron.right") { navigation.goForward() }
                .keyboardShortcut("]")
                .disabled(!navigation.canGoForward)
                .help("Forward")
        }
        titleItem
    }

    /// On macOS 26 toolbar items sit on glass, which a heading shouldn't.
    @ToolbarContentBuilder
    private var titleItem: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { SettingsTitle(navigation: navigation) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { SettingsTitle(navigation: navigation) }
        }
    }
}

private struct SettingsTitle: View {

    let navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(navigation.isSearching ? "Search" : navigation.pane.title)
                .font(.system(size: 13, weight: .semibold))
            Text(navigation.isSearching ? "Results for “\(navigation.query)”" : navigation.pane.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.leading, 6)
        // One width for every page, so the toolbar doesn't shift as the title changes.
        .frame(width: 300, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// What the search field found, in place of the page, until you pick one or clear the search.
private struct SettingsSearchResults: View {

    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        let results = SettingsSearch.results(for: navigation.query)
        if results.isEmpty {
            ContentUnavailableView.search(text: navigation.query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
        } else {
            SettingsPage {
                SettingsSection(results.count == 1 ? "1 result" : "\(results.count) results") {
                    ForEach(results) { result in
                        Button {
                            navigation.open(result)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: result.pane.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(result.location)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Live copy of the menu bar item and its popover, drawn at the size the real one is. It runs on demo events
/// rather than yours, but shares your settings, so every change shows up as you make it. When everything is
/// switched on and it's taller than the panel, it scales down to fit rather than being cut off.
private struct SettingsPreview: View {

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemScheme
    @State private var scheme: ColorScheme?
    @State private var demo: AppState?
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        let previewScheme = scheme ?? systemScheme

        VStack(spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                schemeButton(.light, symbol: "sun.max", label: "Light", current: previewScheme)
                schemeButton(.dark, symbol: "moon", label: "Dark", current: previewScheme)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // GeometryReader takes the space it's offered and doesn't report the popover's height
            // back up, so the inspector column can't get into a resize loop with it.
            GeometryReader { geometry in
                if let demo {
                    let available = max(geometry.size.height - 16, 1)
                    let scale = naturalHeight > available ? available / naturalHeight : 1
                    preview(demo, scheme: previewScheme)
                        // Lay out at full natural height, measure it, then shrink the drawing only if needed.
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: scale < 1 ? .top : .center)
                        .padding(.top, scale < 1 ? 8 : 0)
                        .environment(demo)
                }
            }
            .clipped()

            Text("Preview uses sample events. Changes apply instantly.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
        .background { Backdrop().ignoresSafeArea() }
        .environment(\.colorScheme, previewScheme)
        .inspectorColumnWidth(300 * appState.preferences.textSize.scale + 48)
        .task {
            let state = AppState(preferences: appState.preferences, eventService: DemoEventStore())
            await state.start()
            demo = state
        }
        .onDisappear { demo?.stop() }
    }

    private func preview(_ demo: AppState, scheme: ColorScheme) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Group {
                if demo.preferences.menuBarFormat.isIconOnly {
                    Image(nsImage: MenuBarIcon.image)
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                } else {
                    Text(demo.menuBarTitle)
                        .font(.system(size: NSFont.systemFontSize).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .menuBarCapsule()
            // The same view the popover shows, so size and content always match.
            PopoverView(openSettings: {})
                .clipShape(.rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.08), lineWidth: 0.5)
                }
                // A shadow strong enough to lift the preview off the backdrop in both light and dark.
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 16, y: 6)
        }
        .frame(width: 300 * demo.preferences.textSize.scale)
    }

    private func schemeButton(_ value: ColorScheme, symbol: String, label: String, current: ColorScheme) -> some View {
        Button {
            scheme = value
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(current == value ? Color.orbitTeal : Color.secondary)
        .help("\(label) preview")
        .accessibilityLabel("\(label) preview")
    }
}

/// A plain matte surface behind the preview: the grey macOS puts behind documents, in light or dark.
private struct Backdrop: View {

    var body: some View {
        Color(nsColor: .underPageBackgroundColor)
    }
}

private extension View {
    /// Liquid Glass on macOS 26, as the real menu bar draws it; a frosted capsule on macOS 15.
    @ViewBuilder
    func menuBarCapsule() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
