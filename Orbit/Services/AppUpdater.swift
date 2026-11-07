import AppKit
import Observation
import Sparkle

/// What the calendar and Settings show about updates. Sparkle does the work; see `AppUpdater`.
@MainActor
@Observable
final class UpdateState {

    /// A newer version Sparkle has found and you haven't skipped, for the row at the bottom of the calendar.
    var availableVersion: String?
    var lastChecked: Date?
    /// Checks now and shows Sparkle's window. Set by the app; does nothing in tests and previews.
    @ObservationIgnored var checkNow: @MainActor () -> Void = {}
}

/// Runs Sparkle, which finds a new version in the release's appcast, shows its notes, and downloads,
/// verifies and installs it, relaunching Orbit. The windows are Sparkle's own.
@MainActor
final class AppUpdater: NSObject, @preconcurrency SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {

    private let state: UpdateState
    private var controller: SPUStandardUpdaterController?

    init(state: UpdateState) {
        self.state = state
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        state.lastChecked = controller.updater.lastUpdateCheckDate
        state.checkNow = { [weak self] in
            // Orbit has no Dock icon, so bring it forward or Sparkle's window can open behind everything.
            NSApp.activate()
            self?.controller?.checkForUpdates(nil)
        }
    }

    /// Follows the setting in General › Updates. Debug builds never check by themselves, so a build
    /// you're working on isn't offered the released version.
    func setChecksAutomatically(_ enabled: Bool) {
        #if DEBUG
        controller?.updater.automaticallyChecksForUpdates = false
        #else
        controller?.updater.automaticallyChecksForUpdates = enabled
        #endif
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state.availableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        state.availableVersion = nil
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        state.lastChecked = updater.lastUpdateCheckDate
    }

    // MARK: SPUStandardUserDriverDelegate

    /// A menu bar app is rarely frontmost, so Sparkle wants to hear how it will handle a window appearing.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Brings the window found by a background check to the front, like any other update prompt.
        if handleShowingUpdate { NSApp.activate() }
    }
}
