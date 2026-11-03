import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item and the calendar popover.
@MainActor
final class StatusItemController: NSObject {

    private let appState: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let openSettings: @MainActor () -> Void

    init(appState: AppState, openSettings: @escaping @MainActor () -> Void) {
        self.appState = appState
        self.openSettings = openSettings
        super.init()

        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let content = PopoverView(
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            },
            close: { [weak self] in self?.popover.performClose(nil) }
        )
        let controller = NSHostingController(rootView: content.environment(appState))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        updateTitle()
    }

    /// Re-renders the title whenever any state it reads changes.
    private func updateTitle() {
        withObservationTracking {
            let isIconOnly = appState.preferences.menuBarFormat.isIconOnly
            statusItem.button?.image = isIconOnly ? MenuBarIcon.image : nil
            statusItem.button?.title = appState.menuBarTitle
            statusItem.button?.setAccessibilityLabel(isIconOnly ? "Orbit" : nil)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    /// Left click toggles the calendar; right click (or control-click) shows the app menu, the only place to quit.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showAppMenu()
        } else {
            togglePopover()
        }
    }

    private func showAppMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsChosen), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Orbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Attaching the menu only for this click keeps left clicks opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func settingsChosen() {
        openSettings()
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.behavior = SystemIntegration.popoverBehavior(keepCalendarOnTop: appState.preferences.keepCalendarOnTop)
        appState.showToday()
        appState.detailEventID = nil
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }
}

extension StatusItemController: NSPopoverDelegate {

    func popoverDidClose(_ notification: Notification) {
        appState.detailEventID = nil
    }
}
