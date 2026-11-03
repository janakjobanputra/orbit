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
        applyPreferences()
        Task { await appState.start() }
        // For development: `Orbit.app/Contents/MacOS/Orbit -OpenSettingsOnLaunch YES`.
        if UserDefaults.standard.bool(forKey: "OpenSettingsOnLaunch") {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    /// Applies app-wide preferences now and again whenever they change.
    private func applyPreferences() {
        withObservationTracking {
            SystemIntegration.apply(appState.preferences)
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyPreferences() }
        }
    }

    private func showSettings() {
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
