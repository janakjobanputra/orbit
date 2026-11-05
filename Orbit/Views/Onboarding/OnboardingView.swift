import AppKit
import KeyboardShortcuts
import SwiftUI

/// The welcome tour: calendar access, how the calendar looks, what the menu bar shows, and a few tips.
/// Every choice is a real setting, changed as you pick it, so the tour is also the quickest way to set Orbit up.
struct OnboardingView: View {

    @Environment(AppState.self) private var appState
    @State var step: OnboardingStep = .welcome
    /// Sample events for the previews, so they look full before you've connected anything.
    @State private var demo: AppState?
    /// Called with true from the last page's Open Orbit button, false when the tour is skipped.
    let finish: (_ openCalendar: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomePage()
                case .calendars: CalendarsPage()
                case .view: ViewPage(demo: demo)
                case .menuBar: MenuBarPage(demo: demo)
                case .tips: TipsPage()
                case .done: DonePage()
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)

            footer
        }
        .frame(width: 720, height: 560)
        .tint(.orbitTeal)
        .background(Color(nsColor: .windowBackgroundColor))
        // Made again on each page, so the sample day is laid out around now however long the tour has been open.
        .task(id: step) {
            let state = AppState(preferences: appState.preferences, eventService: DemoEventStore())
            await state.start()
            demo?.stop()
            demo = state
        }
        .onDisappear { demo?.stop() }
        // Back from System Settings: show the access or accounts you just changed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshCalendars()
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip Tour") { finish(false) }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
                .opacity(step.isLast ? 0 : 1)
                .disabled(step.isLast)
            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases) { page in
                    Circle()
                        .fill(page == step ? Color.orbitTeal : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            Spacer()
            HStack {
                if let previous = step.previous {
                    Button("Back") { go(to: previous) }
                        .controlSize(.large)
                }
                Button(step.continueTitle) {
                    if let next = step.next { go(to: next) } else { finish(true) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(minWidth: 170, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func go(to page: OnboardingStep) {
        withAnimation(.easeOut(duration: 0.22)) { step = page }
    }
}

// MARK: - Pages

private struct WelcomePage: View {

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            OrbitMark(size: 128, animated: true)
            Text("Welcome to Orbit")
                .font(.system(size: 30, weight: .bold))
            Text("Your whole day, one click away in the menu bar. This quick tour sets Orbit up the way you like it, and takes about a minute.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Spacer()
        }
    }
}

private struct CalendarsPage: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                symbol: "calendar",
                title: "Connect your calendars",
                subtitle: "Orbit shows the calendars already on your Mac, so there's no account to make. Your events stay on your Mac."
            )
            access
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.orbitTeal)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use Google, Outlook or Exchange?")
                        .font(.headline)
                    Text("Add the account in System Settings › Internet Accounts and turn on Calendars. It shows up in Orbit by itself, no restart needed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Internet Accounts…") { NSWorkspace.shared.open(SystemSettingsPane.internetAccounts) }
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var access: some View {
        switch appState.access {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                Text("Orbit needs your permission to read your calendars.")
                Button("Allow Calendar Access") { Task { await appState.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                Label("Calendar access is turned off", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Turn on Orbit under Privacy & Security › Calendars. Orbit notices as soon as you do.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings") { NSWorkspace.shared.open(SystemSettingsPane.calendarPrivacy) }
            }
        case .granted:
            VStack(alignment: .leading, spacing: 10) {
                Label(sources.isEmpty ? "Orbit can read your calendars" : "Orbit can see these calendars", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if sources.isEmpty {
                    Text("There aren't any calendars on this Mac yet. Add an account below and it'll appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sources, id: \.name) { source in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(source.name)
                                        .fontWeight(.medium)
                                        .frame(width: 130, alignment: .leading)
                                        .lineLimit(1)
                                    Text(source.calendars)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Each account and its calendars: "iCloud — Home, Work".
    private var sources: [(name: String, calendars: String)] {
        Dictionary(grouping: appState.calendars, by: \.sourceTitle)
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, calendars: $0.value.map(\.title).joined(separator: ", ")) }
    }
}

private struct ViewPage: View {

    @Environment(AppState.self) private var appState
    let demo: AppState?

    var body: some View {
        @Bindable var preferences = appState.preferences
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(symbol: "rectangle.split.1x2", title: "Pick how you see your day", subtitle: "Click Orbit in the menu bar and this is what opens.")
                ChoiceCard(
                    symbol: "calendar.day.timeline.left", title: "Day",
                    detail: "Today hour by hour, like Calendar, with a line at the current time.",
                    isSelected: preferences.eventsView == .day
                ) { preferences.eventsView = .day }
                ChoiceCard(
                    symbol: "list.bullet.rectangle", title: "Agenda",
                    detail: "A list of the days ahead, with your next meeting at the top.",
                    isSelected: preferences.eventsView == .agenda
                ) { preferences.eventsView = .agenda }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spacing").font(.headline)
                    Picker("Spacing", selection: $preferences.eventDensity) {
                        ForEach(Density.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
            }
            PopoverPreview(demo: demo)
        }
    }
}

private struct MenuBarPage: View {

    @Environment(AppState.self) private var appState
    let demo: AppState?

    private let presets = MenuBarPreset.allCases.filter { $0 != .custom }

    var body: some View {
        @Bindable var preferences = appState.preferences
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(symbol: "menubar.rectangle", title: "Choose what the menu bar shows", subtitle: "Pick one now. You can build your own under Settings › Display.")
            MenuBarMock(demo: demo)
            VStack(spacing: 2) {
                ForEach(presets) { preset in
                    Button {
                        preferences.menuBarFormat.preset = preset
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preferences.menuBarFormat.preset == preset ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(preferences.menuBarFormat.preset == preset ? Color.orbitTeal : .secondary)
                                .font(.title3)
                            Text(preset.label).fontWeight(.medium).frame(width: 70, alignment: .leading)
                            Text(preset.summary).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(
                            preferences.menuBarFormat.preset == preset ? Color.orbitTeal.opacity(0.1) : .clear,
                            in: .rect(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TipsPage: View {

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(symbol: "sparkles", title: "A few handy things", subtitle: "Orbit stays out of the way until you need it.")
            VStack(alignment: .leading, spacing: 16) {
                Tip(symbol: "keyboard", title: "\(shortcut(.toggleCalendar, fallback: "⇧⌘C")) opens Orbit from anywhere", detail: "Esc closes it again. Change the shortcuts in Settings › General.")
                Tip(symbol: "video", title: "\(shortcut(.joinNextMeeting, fallback: "⇧⌘J")) joins your next meeting", detail: "Zoom, Meet, Teams, Webex and more, straight from the invitation.")
                Tip(symbol: "cursorarrow.click.2", title: "Right-click Orbit for Settings and Quit", detail: "Hold ⌘ and drag it to move it along the menu bar.")
                Tip(symbol: "clock", title: "Two clocks in your menu bar?", detail: "Shrink Apple's clock in System Settings, and let Orbit show the date and time.") {
                    Button("Clock Options…") { NSWorkspace.shared.open(SystemSettingsPane.clockOptions) }
                }
            }
            Divider()
            Toggle("Open Orbit when you log in", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? LaunchAtLogin.setEnabled(enabled)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ name: KeyboardShortcuts.Name, fallback: String) -> String {
        KeyboardShortcuts.getShortcut(for: name)?.description ?? fallback
    }
}

private struct DonePage: View {

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            OrbitMark(size: 96, animated: true)
            Text("You're all set")
                .font(.system(size: 30, weight: .bold))
            Text("Orbit lives in your menu bar, up by the clock. Click it any time to see your day.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("You can take this tour again from Settings › Help.")
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

// MARK: - Pieces

private struct PageHeader: View {

    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Color.orbitTeal)
            }
            .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChoiceCard: View {

    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.orbitTeal : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(isSelected ? Color.orbitTeal.opacity(0.1) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.orbitTeal : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct Tip<Accessory: View>: View {

    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.orbitTeal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension Tip where Accessory == EmptyView {
    init(symbol: String, title: String, detail: String) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

/// The calendar as it opens from the menu bar, with sample events, shrunk to fit beside the choices.
private struct PopoverPreview: View {

    let demo: AppState?
    private let scale: CGFloat = 0.78

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let demo {
                PopoverView(openSettings: {})
                    .environment(demo)
                    .fixedSize(horizontal: true, vertical: true)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
                    .scaleEffect(scale, anchor: .topLeading)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 300 * scale, height: 430, alignment: .topLeading)
        // A taller calendar fades out at the bottom rather than running into the buttons.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .clipped()
        .accessibilityLabel("Preview of the calendar with sample events")
    }
}

/// A strip of menu bar with Orbit in it, showing the style you've picked.
struct MenuBarMock: View {

    @Environment(AppState.self) private var appState
    let demo: AppState?

    /// The title with a made-up meeting a few minutes away, so the styles that show your next meeting always have
    /// one to show, however long the tour has been open.
    static func sampleTitle(_ preferences: Preferences, now: Date, calendar: Calendar) -> String {
        let meeting = CalendarEvent(
            id: "sample", title: "Design review", start: now.addingTimeInterval(12 * 60), end: now.addingTimeInterval(57 * 60),
            isAllDay: false, calendarID: "sample", color: .fallback, location: nil, meetingURL: nil
        )
        return MenuBarFormatter(format: preferences.menuBarFormat, leadMinutes: max(preferences.nextEventLeadMinutes, 15), calendar: calendar)
            .title(now: now, events: [meeting])
    }

    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Group {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "magnifyingglass")
            }
            .foregroundStyle(.secondary)
            Group {
                if appState.preferences.menuBarFormat.isIconOnly {
                    Image(nsImage: MenuBarIcon.image).renderingMode(.template)
                } else {
                    TimelineView(.everyMinute) { context in
                        Text(Self.sampleTitle(appState.preferences, now: context.date, calendar: appState.calendar))
                            .font(.system(size: NSFont.systemFontSize).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Color.orbitTeal.opacity(0.18), in: .capsule)
            .overlay { Capsule().strokeBorder(Color.orbitTeal.opacity(0.6)) }
            .animation(.default, value: appState.preferences.menuBarFormat)
            Image(systemName: "switch.2").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.bar, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)) }
        .accessibilityElement(children: .combine)
    }
}

/// Orbit's logo drawn in SwiftUI: a ring, a planet at its centre and a moon going round, as on the website.
struct OrbitMark: View {

    let size: CGFloat
    var animated = false
    /// One trip round the ring.
    private let period: TimeInterval = 6

    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            Canvas { canvas, area in
                draw(in: &canvas, area: area, angle: angle(at: context.date))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Where the moon is: up and to the right, as in the logo, then round once every `period`.
    private func angle(at date: Date) -> Angle {
        guard animated else { return .degrees(-45) }
        return .degrees(-45 + date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360)
    }

    private func draw(in canvas: inout GraphicsContext, area: CGSize, angle: Angle) {
        let unit = area.width / 100
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r * unit, y: c.y - r * unit, width: 2 * r * unit, height: 2 * r * unit))
        }
        canvas.stroke(circle(center, 36), with: .color(.orbitTeal.opacity(0.4)), lineWidth: 8 * unit)
        canvas.fill(circle(center, 19), with: .color(.orbitTeal))
        let moon = CGPoint(x: center.x + 36 * unit * cos(angle.radians), y: center.y + 36 * unit * sin(angle.radians))
        canvas.fill(circle(moon, 10), with: .color(.orbitTeal))
    }
}

// MARK: - Window

/// Shows the tour in its own window and brings it to the front, since Orbit has no Dock icon.
@MainActor
final class OnboardingController {

    private var window: NSWindow?
    private let appState: AppState
    private let record: OnboardingRecord
    private let openCalendar: () -> Void

    init(appState: AppState, record: OnboardingRecord, openCalendar: @escaping () -> Void) {
        self.appState = appState
        self.record = record
        self.openCalendar = openCalendar
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = OnboardingView { [weak self] open in self?.finish(openCalendar: open) }
            .environment(appState)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Orbit"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing the window counts as finishing: the tour is in Settings › Help if you want it back.
                self?.record.markSeen()
                self?.window = nil
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func finish(openCalendar open: Bool) {
        record.markSeen()
        window?.close()
        if open { openCalendar() }
    }
}
