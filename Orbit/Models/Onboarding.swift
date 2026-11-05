import Foundation

/// The welcome tour shown the first time Orbit opens, one page at a time.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, calendars, view, menuBar, tips, done

    var id: Self { self }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }

    /// The label on the button that moves you on.
    var continueTitle: String {
        switch self {
        case .welcome: "Get Started"
        case .done: "Open Orbit"
        default: "Continue"
        }
    }
}

/// Whether to show the welcome tour, remembered in UserDefaults.
@MainActor
struct OnboardingRecord {

    static let key = "hasSeenWelcomeTour"

    let defaults: UserDefaults

    /// Shows the tour on a fresh install only. Someone updating from a version without the tour has already
    /// answered the calendar-access question, so they're treated as having seen it.
    func shouldShowTour(access: EventStoreService.Access) -> Bool {
        if defaults.object(forKey: Self.key) == nil {
            // Remembered either way, so granting access halfway through and quitting still brings the tour back.
            defaults.set(access != .notDetermined, forKey: Self.key)
        }
        return !defaults.bool(forKey: Self.key)
    }

    func markSeen() {
        defaults.set(true, forKey: Self.key)
    }
}

/// Where the tour's buttons send you in System Settings.
enum SystemSettingsPane {
    static let internetAccounts = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!
    static let calendarPrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    /// Where the clock options are: Control Center on macOS 15, Menu Bar on macOS 26.
    static let clockOptions = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
}
