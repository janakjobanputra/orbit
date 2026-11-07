import KeyboardShortcuts
import Observation
import SwiftUI

@main
struct OrbitApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var statusItemController: StatusItemController?
    private var settingsWindow: NSWindow?
    private var updater: AppUpdater?
    private var telemetry: Telemetry?
    private var crashDiagnostics: CrashDiagnostics?
    private lazy var welcomeTour = OnboardingController(appState: appState, record: OnboardingRecord(defaults: .standard)) { [weak self] in
        self?.statusItemController?.togglePopover()
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        statusItemController = StatusItemController(appState: appState) { [weak self] in
            self?.showSettings()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleCalendar) { [weak self] in
            self?.statusItemController?.togglePopover()
        }
        KeyboardShortcuts.onKeyUp(for: .joinNextMeeting) { [weak self] in
            self?.appState.joinNextMeeting()
        }
        updater = AppUpdater(state: appState.updates)
        applyPreferences()
        appState.showWelcomeTour = { [weak self] in self?.welcomeTour.show() }
        Task { await startWithWelcomeTour() }
        startTelemetry()
        // For development: `Orbit.app/Contents/MacOS/Orbit -OpenSettingsOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "OpenSettingsOnLaunch") {
            showSettings()
        }
    }

    /// A fresh install gets the welcome tour, which asks for calendar access itself; anyone else is asked straight away
    /// if they somehow haven't been yet. `-ShowWelcomeTour YES` shows the tour anyway, for development.
    private func startWithWelcomeTour() async {
        await appState.start(askForAccess: false)
        let record = OnboardingRecord(defaults: .standard)
        if record.shouldShowTour(access: appState.access) || UserDefaults.standard.bool(forKey: "ShowWelcomeTour") {
            welcomeTour.show()
        } else if appState.access == .notDetermined {
            await appState.requestAccess()
        }
    }

    /// Release builds only, so working on Orbit never adds to the numbers.
    private func startTelemetry() {
        #if !DEBUG
        let telemetry = Telemetry(appState: appState)
        self.telemetry = telemetry
        crashDiagnostics = CrashDiagnostics { crashes in
            Task { await telemetry.send(crashes) }
        }
        Task {
            // Wakes hourly so a Mac left on is still counted; the report itself goes at most once a day.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await telemetry.sendUsageIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    /// Applies app-wide preferences now and again whenever they change.
    private func applyPreferences() {
        withObservationTracking {
            SystemIntegration.apply(appState.preferences)
            updater?.setChecksAutomatically(appState.preferences.checkForUpdates)
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyPreferences() }
        }
    }

    private func showSettings() {
        appState.refreshCalendars()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(appState))
            // Let SwiftUI's navigation title and toolbar drive the window's unified glass toolbar.
            controller.sceneBridgingOptions = [.title, .toolbars]
            // The window owns its size. Letting SwiftUI's content size drive it loops when the
            // full-size popover preview is taller than the window, which AppKit kills the app for.
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Orbit Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            // The toolbar draws the page's title and subtitle itself, on two lines.
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 900, height: 700)
            window.setContentSize(NSSize(width: 1000, height: 860))
            window.setFrameAutosaveName("OrbitSettingsWindow")
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
