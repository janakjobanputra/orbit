import XCTest
@testable import Orbit

final class SettingsSearchTests: XCTestCase {

    private func titles(_ query: String) -> [String] {
        SettingsSearch.results(for: query).map(\.title)
    }

    func testFindsSettingsByTitleSectionAndOtherWords() {
        XCTAssertEqual(titles("declined").first, "Show declined events")
        XCTAssertEqual(titles("launch").first, "Launch at login")
        XCTAssertEqual(titles("24 hour").first, "Clock")
        XCTAssertEqual(titles("json").first, "Export settings")
        XCTAssertTrue(titles("dark").contains("Appearance"))
    }

    func testEveryWordMustMatchInAnyOrderAndCase() {
        XCTAssertEqual(titles("EVENTS HIDE PAST").first, "Hide past events")
        XCTAssertEqual(titles("declined zebra"), [])
    }

    func testABlankSearchFindsNothing() {
        XCTAssertEqual(titles("   "), [])
    }

    func testSettingsComeAheadOfHelpAnswers() throws {
        let results = SettingsSearch.results(for: "menu bar")
        let firstHelp = try XCTUnwrap(results.firstIndex { $0.helpQuestion != nil })
        XCTAssertTrue(results[..<firstHelp].allSatisfy { $0.helpQuestion == nil })
        XCTAssertTrue(results[firstHelp...].allSatisfy { $0.helpQuestion != nil })
    }

    func testTitlesStartingWithTheSearchComeFirst() {
        let results = SettingsSearch.results(for: "week")
        XCTAssertEqual(results.first?.title, "Week numbers")
    }

    func testEveryPaneCanBeFoundAndHelpQuestionsAreIndexed() {
        XCTAssertEqual(Set(SettingsSearch.index.map(\.pane)), Set(SettingsPane.allCases))
        XCTAssertEqual(SettingsSearch.index.filter { $0.helpQuestion != nil }.count, HelpTopic.all.count)
        XCTAssertEqual(Set(SettingsSearch.index.map(\.id)).count, SettingsSearch.index.count, "IDs are unique")
    }

    func testLocationNamesThePaneAndSection() throws {
        let result = try XCTUnwrap(SettingsSearch.results(for: "declined").first)
        XCTAssertEqual(result.location, "Display › Layout")
    }
}

@MainActor
final class SettingsNavigationTests: XCTestCase {

    func testBackAndForwardRetraceThePagesVisited() {
        let navigation = SettingsNavigation(pane: .general)
        XCTAssertFalse(navigation.canGoBack)
        XCTAssertFalse(navigation.canGoForward)

        navigation.open(.display)
        navigation.open(.help)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .display)
        XCTAssertTrue(navigation.canGoForward)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .general)
        XCTAssertFalse(navigation.canGoBack)
        navigation.goForward()
        navigation.goForward()
        XCTAssertEqual(navigation.pane, .help)
        XCTAssertFalse(navigation.canGoForward)
    }

    func testOpeningAPageClearsWhatWasAhead() {
        let navigation = SettingsNavigation(pane: .general)
        navigation.open(.display)
        navigation.goBack()
        navigation.open(.about)
        XCTAssertFalse(navigation.canGoForward)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .general)
    }

    func testOpeningTheSamePageAddsNoHistoryButEndsASearch() {
        let navigation = SettingsNavigation(pane: .general)
        navigation.query = "dark"
        XCTAssertTrue(navigation.isSearching)
        navigation.open(.general)
        XCTAssertFalse(navigation.canGoBack)
        XCTAssertFalse(navigation.isSearching)
    }

    func testBlankSearchIsNotASearch() {
        let navigation = SettingsNavigation(pane: .general)
        navigation.query = "   "
        XCTAssertFalse(navigation.isSearching)
    }

    func testChoosingAResultOpensItsPageAndAsksForItsSection() throws {
        let navigation = SettingsNavigation(pane: .general)
        navigation.query = "declined"
        navigation.open(try XCTUnwrap(SettingsSearch.results(for: navigation.query).first))
        XCTAssertEqual(navigation.pane, .display)
        XCTAssertEqual(navigation.requestedSection, "Layout")
        XCTAssertFalse(navigation.isSearching)
        navigation.goBack()
        XCTAssertEqual(navigation.pane, .general, "A result counts as a visit")
    }

    func testChoosingAHelpResultAsksToOpenThatAnswer() throws {
        let navigation = SettingsNavigation(pane: .general)
        let result = try XCTUnwrap(SettingsSearch.index.first { $0.helpQuestion != nil })
        navigation.open(result)
        XCTAssertEqual(navigation.pane, .help)
        XCTAssertEqual(navigation.requestedHelpQuestion, result.title)
    }
}
