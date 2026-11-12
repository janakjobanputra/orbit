import AppKit

/// Opens meeting links in the call's own app when it's installed: Zoom and Teams through their app links,
/// Google Meet in the Meet app installed from Chrome. Anything else, or if that fails, goes to the browser.
@MainActor
enum MeetingOpener {

    /// The Google Meet app Chrome installs from meet.google.com (Install Google Meet, in the address bar).
    static let meetChromeAppID = "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan"

    static func open(_ url: URL, workspace: NSWorkspace = .shared) {
        if let appLink = MeetingAppLink.appURL(for: url),
           workspace.urlForApplication(toOpen: appLink) != nil,
           workspace.open(appLink) {
            return
        }
        if isMeet(url), let meetApp = workspace.urlForApplication(withBundleIdentifier: meetChromeAppID) {
            workspace.open([url], withApplicationAt: meetApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard error != nil else { return }
                // Couldn't hand it to the Meet app: the browser, as for any other call.
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
            return
        }
        workspace.open(url)
    }

    /// The app Join will open the call in, for its icon on the Join button. Nil when it's the browser.
    static func app(for url: URL, workspace: NSWorkspace = .shared) -> URL? {
        if let appLink = MeetingAppLink.appURL(for: url), let app = workspace.urlForApplication(toOpen: appLink) {
            return app
        }
        if isMeet(url) { return workspace.urlForApplication(withBundleIdentifier: meetChromeAppID) }
        return nil
    }

    static func icon(for url: URL, workspace: NSWorkspace = .shared) -> NSImage? {
        app(for: url, workspace: workspace).map { workspace.icon(forFile: $0.path) }
    }

    private static func isMeet(_ url: URL) -> Bool {
        url.host?.lowercased() == "meet.google.com"
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

    /// `activate: false` opens it behind the call, so the meeting stays in front.
    static func open(activate: Bool = true) {
        guard let appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
