import AppKit

/// Opens meeting links, in the call's own app when it's installed.
@MainActor
enum MeetingOpener {

    static func open(_ url: URL, workspace: NSWorkspace = .shared) {
        if let appURL = MeetingAppLink.appURL(for: url),
           workspace.urlForApplication(toOpen: appURL) != nil,
           workspace.open(appURL) {
            return
        }
        workspace.open(url)
    }
}

/// Granola, the meeting notes app. It has no link to a particular meeting, but it notices the call itself,
/// so opening it is enough to start taking notes.
@MainActor
enum Granola {

    static let bundleID = "com.granola.app"

    static var isInstalled: Bool { appURL != nil }

    private static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func open() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
