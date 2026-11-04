import XCTest
@testable import Orbit

final class ReleaseNotesTests: XCTestCase {

    private let body = """
    **Install:** download **Orbit-v1.1.3.dmg** below, open it and drag Orbit into Applications.

    **Requires** macOS 15 Sequoia or later.

    ### What's new in 1.1.3
    - **Invitations** you haven't accepted are marked.
    - Events spacing also sets the Day view's hour height.

    On 1.1.2? Orbit will offer this update.
    """

    func testStartsAtWhatsNewWhenThereIsOne() {
        let lines = ReleaseNotes.lines(from: body)
        XCTAssertEqual(lines.first, .heading("What's new in 1.1.3"))
        XCTAssertFalse(lines.contains { if case .paragraph(let text) = $0 { String(text.characters).contains("Install") } else { false } })
    }

    func testBulletsKeepTheirInlineFormatting() throws {
        let bullets = ReleaseNotes.lines(from: body).compactMap { line -> AttributedString? in
            if case .bullet(let text) = line { text } else { nil }
        }
        XCTAssertEqual(bullets.count, 2)
        let first = try XCTUnwrap(bullets.first)
        XCTAssertEqual(String(first.characters), "Invitations you haven't accepted are marked.")
        XCTAssertTrue(first.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "**bold** stays bold")
    }

    func testNotesWithoutAWhatsNewHeadingAreShownWhole() {
        let lines = ReleaseNotes.lines(from: "Fixed 503 errors when installing.\n\n* Faster sync")
        XCTAssertEqual(lines.count, 2)
        if case .bullet(let text) = lines[1] { XCTAssertEqual(String(text.characters), "Faster sync") } else { XCTFail("Expected a bullet") }
    }

    func testEmptyNotesHaveNoLines() {
        XCTAssertTrue(ReleaseNotes.lines(from: "  \n\n").isEmpty)
    }

    func testReleaseInfoKeepsTheNotes() throws {
        let json = #"{"tag_name": "v1.1.3", "html_url": "https://github.com/janakjobanputra/orbit/releases/tag/v1.1.3", "body": "- Fixed it", "assets": []}"#
        XCTAssertEqual(try ReleaseInfo.decode(Data(json.utf8)).notes, "- Fixed it")
        let noBody = #"{"tag_name": "v1.1.3", "html_url": "https://github.com/janakjobanputra/orbit/releases/tag/v1.1.3", "assets": []}"#
        XCTAssertEqual(try ReleaseInfo.decode(Data(noBody.utf8)).notes, "")
    }
}

@MainActor
final class UpdatePromptTests: XCTestCase {

    private var defaults: UserDefaults!
    private var now = TestSupport.date(2026, 11, 4, 9)
    private var prompted: [String] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: "OrbitUpdatePrompt-\(UUID().uuidString)")
        prompted = []
    }

    private func release(_ version: String) -> ReleaseInfo {
        ReleaseInfo(version: AppVersion(version)!, pageURL: URL(string: "https://example.com/\(version)")!, downloadURL: nil, notes: "- Fixes")
    }

    private func checker(latest: String) -> UpdateChecker {
        let updates = UpdateChecker(
            currentVersion: AppVersion("1.1.2")!, fetcher: StubReleaseFetcher(release: release(latest)), defaults: defaults
        ) { [unowned self] in now }
        updates.presentPrompt = { [unowned self] in prompted.append($0.version.description) }
        return updates
    }

    func testAutomaticCheckShowsTheDialogForANewVersion() async {
        await checker(latest: "1.1.3").checkIfDue()
        XCTAssertEqual(prompted, ["1.1.3"])
    }

    func testNoDialogWhenUpToDate() async {
        await checker(latest: "1.1.2").checkIfDue()
        XCTAssertEqual(prompted, [])
    }

    func testSkippedVersionIsNotOfferedAgainAutomatically() async {
        let updates = checker(latest: "1.1.3")
        await updates.checkIfDue()
        updates.skip(release("1.1.3"))
        XCTAssertNil(updates.bannerRelease, "Skipping also hides the banner in the calendar")

        now = now.addingTimeInterval(2 * UpdateChecker.interval)
        let relaunched = checker(latest: "1.1.3")
        await relaunched.checkIfDue()
        XCTAssertEqual(prompted, ["1.1.3"], "Only the first check prompted")
        XCTAssertNil(relaunched.bannerRelease)
    }

    func testANewerVersionThanTheSkippedOneIsOffered() async {
        let updates = checker(latest: "1.1.3")
        updates.skip(release("1.1.3"))
        let later = checker(latest: "1.1.4")
        await later.checkIfDue()
        XCTAssertEqual(prompted, ["1.1.4"])
        XCTAssertEqual(later.bannerRelease?.version, AppVersion("1.1.4"))
    }

    func testRemindMeLaterWaitsADay() async {
        let updates = checker(latest: "1.1.3")
        await updates.checkIfDue()
        updates.remindLater()

        now = now.addingTimeInterval(UpdateChecker.interval / 2)
        await updates.checkNow()
        XCTAssertFalse(updates.shouldPrompt(release("1.1.3")))

        now = now.addingTimeInterval(UpdateChecker.interval)
        await checker(latest: "1.1.3").checkIfDue()
        XCTAssertEqual(prompted, ["1.1.3", "1.1.3"])
    }

    func testCheckingByHandAlwaysShowsTheDialog() async {
        let updates = checker(latest: "1.1.3")
        updates.skip(release("1.1.3"))
        await updates.checkNowAndPrompt()
        XCTAssertEqual(prompted, ["1.1.3"], "Asking explicitly overrides a skip")
    }
}
