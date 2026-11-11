import AppKit
import Observation
import SwiftUI

/// The floating alert shown shortly before a meeting: one card per meeting coming up, with Join and,
/// when it's installed, Granola for notes.
struct MeetingAlertView: View {

    @Environment(AppState.self) private var appState
    /// Checked once when the alert is built, rather than asking Launch Services on every redraw.
    var showsGranola = Granola.isInstalled

    var body: some View {
        VStack(spacing: 8) {
            ForEach(appState.meetingAlerts, id: \.self) { event in
                MeetingAlertCard(event: event, showsGranola: showsGranola && appState.preferences.meetingAlertShowsGranola)
            }
        }
        .padding(10)
        .frame(width: MeetingAlertView.width)
    }

    static let width: CGFloat = 380
}

private struct MeetingAlertCard: View {

    @Environment(AppState.self) private var appState
    let event: CalendarEvent
    let showsGranola: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.color.color)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)
                    // Built from Text so the times follow the environment's time zone, as the rest of Orbit does.
                    (Text(MeetingAlertSchedule.timing(of: event, now: appState.now) + " · ")
                        + Text(event.start, format: .dateTime.hour().minute())
                        + Text(" – ")
                        + Text(event.end, format: .dateTime.hour().minute()))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Button {
                    appState.dismissAlert(event)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 8) {
                if event.meetingURL != nil {
                    Button {
                        appState.join(fromAlert: event)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                // For calls and meetings with other people; Lunch on your own doesn't need notes.
                if showsGranola && (event.meetingURL != nil || !event.guests.isEmpty) {
                    Button {
                        Granola.open()
                    } label: {
                        Label("Granola", systemImage: "note.text")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Open Granola to take notes")
                }
                if event.meetingURL == nil && !(showsGranola && !event.guests.isEmpty) {
                    Button("Dismiss") { appState.dismissAlert(event) }
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .tint(.orbitTeal)
    }
}

/// Shows and hides the alert panel as `AppState.meetingAlerts` changes, and plays a sound when a new one arrives.
@MainActor
final class MeetingAlertController {

    private let appState: AppState
    private var panel: NSPanel?
    private var shownCount = 0

    init(appState: AppState) {
        self.appState = appState
        follow()
    }

    private func follow() {
        let alerts = withObservationTracking {
            appState.meetingAlerts
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        update(for: alerts)
    }

    private func update(for alerts: [CalendarEvent]) {
        defer { shownCount = alerts.count }
        guard !alerts.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if alerts.count > shownCount, appState.preferences.meetingAlertSound {
            NSSound(named: "Glass")?.play()
        }
        // Wait a turn so SwiftUI has laid out the new list before the panel is sized to it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !self.appState.meetingAlerts.isEmpty else { return }
            self.place(panel)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: MeetingAlertView().environment(appState))
        host.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        // Above other windows and full-screen apps, on every Space, without taking focus from what you're doing.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .alertPanel
        return panel
    }

    /// Top right of the screen you're using, just under the menu bar, where notifications appear.
    private func place(_ panel: NSPanel) {
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
