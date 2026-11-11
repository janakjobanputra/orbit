import Foundation

/// Turns a meeting's web link into the link its desktop app opens directly, so joining skips the browser tab
/// that would only hand over to the app anyway.
enum MeetingAppLink {

    /// The app's own link for the call, or nil when there isn't one Orbit knows to build. Only Zoom and Teams
    /// document one; Google Meet runs in the browser, and Webex's web page already passes the call to its app.
    static func appURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return zoom(url, host: host) }
        if host == "teams.microsoft.com" { return teams(url) }
        return nil
    }

    /// `https://acme.zoom.us/j/123456789?pwd=abc` → `zoommtg://acme.zoom.us/join?action=join&confno=123456789&pwd=abc`.
    private static func zoom(_ url: URL, host: String) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        // Meetings are /j/<number>; webinars /w/<number>. Personal links and others go through the browser.
        guard parts.count >= 2, parts[0] == "j" || parts[0] == "w",
              !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let password = query.first(where: { $0.name == "pwd" })?.value, !password.isEmpty {
            items.append(URLQueryItem(name: "pwd", value: password))
        }
        components.queryItems = items
        return components.url
    }

    /// `https://teams.microsoft.com/l/meetup-join/…` → `msteams:/l/meetup-join/…`, the same path and query.
    private static func teams(_ url: URL) -> URL? {
        let path = url.path(percentEncoded: true)
        guard path.hasPrefix("/l/meetup-join/") else { return nil }
        let query = url.query(percentEncoded: true).map { "?" + $0 } ?? ""
        return URL(string: "msteams:" + path + query)
    }
}
