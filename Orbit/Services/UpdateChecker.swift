import Foundation
import Observation

/// A release version such as `1.2.3`, compared number by number so 1.10 is newer than 1.9.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {

    let parts: [Int]

    /// Accepts `1`, `1.2`, `1.2.3` and a leading `v`, as used in release tags.
    init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    /// The running app's version, from `CFBundleShortVersionString`.
    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        parts + Array(repeating: 0, count: max(0, other.parts.count - parts.count))
    }
}

/// The newest published release on GitHub.
struct ReleaseInfo: Equatable, Sendable {

    let version: AppVersion
    let pageURL: URL
    /// The disk image to download, when the release has one.
    let downloadURL: URL?

    var bestURL: URL { downloadURL ?? pageURL }

    struct NotAVersion: Error {}

    /// Reads GitHub's `releases/latest` response.
    static func decode(_ data: Data) throws -> ReleaseInfo {
        struct Response: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let version = AppVersion(response.tag_name) else { throw NotAVersion() }
        let images = response.assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        let image = images.first { $0.name == "Orbit.dmg" } ?? images.first
        return ReleaseInfo(version: version, pageURL: response.html_url, downloadURL: image?.browser_download_url)
    }
}

protocol ReleaseFetching: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

/// Asks GitHub for the latest release. Sends nothing about you or your calendar.
struct GitHubReleaseFetcher: ReleaseFetching {

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/janakjobanputra/orbit/releases/latest")!

    struct BadResponse: Error {}

    func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BadResponse() }
        return try ReleaseInfo.decode(data)
    }
}

/// Checks GitHub for a newer version of Orbit, automatically once a day or when asked.
@MainActor
@Observable
final class UpdateChecker {

    enum Status: Equatable {
        case idle, checking, upToDate, available(ReleaseInfo), failed
    }

    static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckedKey = "lastUpdateCheck"

    let currentVersion: AppVersion
    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private let fetcher: any ReleaseFetching
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date

    init(
        currentVersion: AppVersion = .current ?? AppVersion("0")!,
        fetcher: any ReleaseFetching = GitHubReleaseFetcher(),
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.defaults = defaults
        self.clock = clock
        lastChecked = defaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = status { release } else { nil }
    }

    /// The automatic check: does nothing if the last successful check was under a day ago.
    func checkIfDue() async {
        if let lastChecked, clock().timeIntervalSince(lastChecked) < Self.interval { return }
        await checkNow()
    }

    func checkNow() async {
        guard status != .checking else { return }
        status = .checking
        do {
            let release = try await fetcher.latestRelease()
            status = release.version > currentVersion ? .available(release) : .upToDate
            lastChecked = clock()
            defaults.set(lastChecked, forKey: Self.lastCheckedKey)
        } catch {
            status = .failed
        }
    }
}
