import XCTest
@testable import Orbit

final class AppVersionTests: XCTestCase {

    func testParsesTagsAndPlainVersions() {
        XCTAssertEqual(AppVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("1.2")?.description, "1.2")
        XCTAssertEqual(AppVersion(" 2 ")?.description, "2")
    }

    func testRejectsAnythingElse() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2-beta"))
    }

    func testComparesNumerically() throws {
        let v = { (s: String) in try XCTUnwrap(AppVersion(s)) }
        XCTAssertLessThan(try v("1.9"), try v("1.10"))
        XCTAssertLessThan(try v("1.0.0"), try v("1.0.1"))
        XCTAssertLessThan(try v("1.2.9"), try v("2"))
        XCTAssertEqual(try v("1.0"), try v("1.0.0"))
        XCTAssertFalse(try v("1.0") < v("1.0.0"))
    }
}

final class ReleaseInfoTests: XCTestCase {

    private func json(tag: String, assets: [String]) -> Data {
        let list = assets.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/janakjobanputra/orbit/releases/download/\#(tag)/\#($0)"}"#
        }
        return Data("""
        {"tag_name": "\(tag)", "html_url": "https://github.com/janakjobanputra/orbit/releases/tag/\(tag)",
         "draft": false, "prerelease": false, "assets": [\(list.joined(separator: ","))]}
        """.utf8)
    }

    func testReadsGitHubsLatestRelease() throws {
        let release = try ReleaseInfo.decode(json(tag: "v1.1.0", assets: ["Orbit-1.1.0.dmg", "Orbit.dmg"]))
        XCTAssertEqual(release.version, AppVersion("1.1.0"))
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/janakjobanputra/orbit/releases/tag/v1.1.0")
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "Orbit.dmg")
    }

    func testFallsBackToAnyDiskImage() throws {
        let release = try ReleaseInfo.decode(json(tag: "v1.1.0", assets: ["notes.txt", "Orbit-1.1.0.dmg"]))
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "Orbit-1.1.0.dmg")
    }

    func testReleaseWithoutDiskImageStillLinksToItsPage() throws {
        let release = try ReleaseInfo.decode(json(tag: "v1.1.0", assets: []))
        XCTAssertNil(release.downloadURL)
        XCTAssertEqual(release.bestURL, release.pageURL)
    }

    func testRejectsTagsThatArentVersions() {
        XCTAssertThrowsError(try ReleaseInfo.decode(json(tag: "nightly", assets: [])))
        XCTAssertThrowsError(try ReleaseInfo.decode(Data("{}".utf8)))
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private final class FakeFetcher: ReleaseFetching, @unchecked Sendable {
        var result: Result<ReleaseInfo, Error>
        var calls = 0
        init(_ result: Result<ReleaseInfo, Error>) { self.result = result }
        func latestRelease() async throws -> ReleaseInfo {
            calls += 1
            return try result.get()
        }
    }

    private struct Offline: Error {}

    private var defaults: UserDefaults!
    private var now = TestSupport.date(2026, 11, 2, 9)

    override func setUp() {
        defaults = UserDefaults(suiteName: "OrbitUpdates-\(UUID().uuidString)")
    }

    private func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/janakjobanputra/orbit/releases/tag/v\(version)")!,
            downloadURL: URL(string: "https://github.com/janakjobanputra/orbit/releases/download/v\(version)/Orbit.dmg")
        )
    }

    private func checker(current: String = "1.0.0", _ fetcher: FakeFetcher) -> UpdateChecker {
        UpdateChecker(currentVersion: AppVersion(current)!, fetcher: fetcher, defaults: defaults) { [unowned self] in now }
    }

    func testNewerReleaseIsOffered() async {
        let updates = checker(FakeFetcher(.success(release("1.1.0"))))
        await updates.checkNow()
        XCTAssertEqual(updates.status, .available(release("1.1.0")))
        XCTAssertEqual(updates.availableRelease, release("1.1.0"))
    }

    func testSameOrOlderReleaseMeansUpToDate() async {
        for latest in ["1.0.0", "0.9"] {
            let updates = checker(FakeFetcher(.success(release(latest))))
            await updates.checkNow()
            XCTAssertEqual(updates.status, .upToDate, latest)
            XCTAssertNil(updates.availableRelease)
        }
    }

    func testFailedCheckIsReported() async {
        let updates = checker(FakeFetcher(.failure(Offline())))
        await updates.checkNow()
        XCTAssertEqual(updates.status, .failed)
        XCTAssertNil(updates.lastChecked, "A failed check is retried next time instead of waiting a day")
    }

    func testAutomaticChecksRunAtMostOnceADay() async {
        let fetcher = FakeFetcher(.success(release("1.0.0")))
        let updates = checker(fetcher)

        await updates.checkIfDue()
        XCTAssertEqual(fetcher.calls, 1)
        XCTAssertEqual(updates.lastChecked, now)

        now = now.addingTimeInterval(23 * 3600)
        await updates.checkIfDue()
        XCTAssertEqual(fetcher.calls, 1)

        now = now.addingTimeInterval(2 * 3600)
        await updates.checkIfDue()
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testLastCheckSurvivesRelaunch() async {
        let fetcher = FakeFetcher(.success(release("1.0.0")))
        await checker(fetcher).checkIfDue()

        let relaunched = checker(fetcher)
        XCTAssertEqual(relaunched.lastChecked, now)
        await relaunched.checkIfDue()
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testManualCheckIgnoresTheDailyLimit() async {
        let fetcher = FakeFetcher(.success(release("1.0.0")))
        let updates = checker(fetcher)
        await updates.checkIfDue()
        await updates.checkNow()
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testAutomaticChecksCanBeTurnedOff() async {
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.checkForUpdates, "On by default")
        preferences.checkForUpdates = false
        XCTAssertFalse(Preferences(defaults: defaults).checkForUpdates)
    }
}
