import Foundation

/// Finds a video-call link in an event's URL, location or notes.
enum MeetingLinkDetector {

    static let knownHosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "whereby.com",
        "around.co",
        "meet.jit.si",
    ]

    /// Returns the first meeting link, checking each field in order. `extraHosts` adds user-defined services.
    static func firstMeetingURL(in fields: [String?], extraHosts: [String] = []) -> URL? {
        for field in fields {
            guard let text = field, !text.isEmpty else { continue }
            if let url = links(in: text).first(where: { isMeetingURL($0, extraHosts: extraHosts) }) {
                return url
            }
        }
        return nil
    }

    static func isMeetingURL(_ url: URL, extraHosts: [String] = []) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        // Teams invitations also carry links to a mobile web page, meeting options and dial-in numbers on
        // teams.microsoft.com, sometimes before the join link itself. Only the join links count.
        if host.hasSuffix("teams.microsoft.com") || host.hasSuffix("teams.live.com") {
            guard host == "teams.microsoft.com" || host == "teams.live.com" else { return false }
            return teamsJoinPaths.contains { url.path.hasPrefix($0) }
        }
        return (knownHosts + extraHosts).contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// `/l/meetup-join/…` in older invitations, `/meet/<id>?p=…` in newer ones.
    static let teamsJoinPaths = ["/l/meetup-join/", "/meet/"]

    /// Web links that aren't video calls, in the order they appear, without duplicates or calendar boilerplate.
    static func otherLinks(in fields: [String?], extraHosts: [String] = [], limit: Int = 6) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for field in fields {
            guard let text = field, !text.isEmpty else { continue }
            for url in links(in: text) where result.count < limit {
                guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                      let host = url.host?.lowercased(),
                      !isMeetingURL(url, extraHosts: extraHosts),
                      !boilerplateHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
                      seen.insert(url.absoluteString).inserted else { continue }
                result.append(url)
            }
        }
        return result
    }

    /// Help links that Google and Microsoft add to every invitation.
    static let boilerplateHosts = ["support.google.com", "g.co", "aka.ms", "go.microsoft.com"]

    /// Made once: building a detector costs far more than running it, and every event's fields go through here.
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func links(in text: String) -> [URL] {
        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
