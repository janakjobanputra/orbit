import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, display, calendars, help, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .display: "Display"
        case .calendars: "Calendars"
        case .help: "Help"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .display: "menubar.rectangle"
        case .calendars: "calendar"
        case .help: "questionmark"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .display: .blue
        case .calendars: .red
        case .help: .orange
        case .about: .indigo
        }
    }
}

/// System Settings–style window: sidebar, grouped form, and a live preview in the inspector.
struct SettingsView: View {

    @AppStorage("settingsPane") private var savedPane: SettingsPane = .general
    /// Kept in State so a `-settingsPane` launch argument only picks the starting pane. Arguments override
    /// UserDefaults for the whole run, so reading the selection straight from storage would pin it there.
    @State private var pane: SettingsPane?

    private var currentPane: SettingsPane { pane ?? savedPane }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { currentPane }, set: { if let new = $0 { pane = new; savedPane = new } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch currentPane {
                case .general: GeneralSettingsTab()
                case .display: DisplaySettingsTab()
                case .calendars: CalendarsSettingsTab()
                case .help: HelpSettingsTab()
                case .about: AboutSettingsTab()
                }
            }
            .navigationTitle(currentPane.title)
            .inspector(isPresented: .constant(true)) {
                SettingsPreview()
                    .interactiveDismissDisabled()
            }
        }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 700, idealHeight: 860)
        .tint(.orbitTeal)
    }
}

/// White glyph on a coloured rounded square, as in System Settings.
private struct SettingsIcon: View {

    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
            .glassEffect(.regular, in: .capsule)
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
