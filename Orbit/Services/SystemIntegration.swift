import AppKit
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let toggleCalendar = Self("toggleCalendar", default: .init(.c, modifiers: [.command, .shift]))
    static let joinNextMeeting = Self("joinNextMeeting", default: .init(.j, modifiers: [.command, .shift]))

    static let allGlobal: [Self] = [.toggleCalendar, .joinNextMeeting]
}

enum SystemIntegration {

    /// Pushes the app-wide preferences (appearance, global shortcuts) into AppKit.
    @MainActor
    static func apply(_ preferences: Preferences) {
        NSApp.appearance = preferences.appearance.nsAppearance
        if preferences.globalShortcutsEnabled {
            KeyboardShortcuts.enable(KeyboardShortcuts.Name.allGlobal)
        } else {
            KeyboardShortcuts.disable(KeyboardShortcuts.Name.allGlobal)
        }
    }

    /// "Keep calendar on top" leaves the popover open until the menu bar item is clicked again.
    static func popoverBehavior(keepCalendarOnTop: Bool) -> NSPopover.Behavior {
        keepCalendarOnTop ? .applicationDefined : .transient
    }
}

enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

extension AppearanceMode {

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
