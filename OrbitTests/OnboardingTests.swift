import XCTest
@testable import Orbit

@MainActor
final class OnboardingTests: XCTestCase {

    private func record() -> OnboardingRecord {
        OnboardingRecord(defaults: UserDefaults(suiteName: "OrbitOnboarding-\(UUID().uuidString)")!)
    }

    func testAFreshInstallSeesTheTourUntilItIsFinished() {
        let record = record()
        XCTAssertTrue(record.shouldShowTour(access: .notDetermined))
        XCTAssertTrue(record.shouldShowTour(access: .notDetermined), "Quitting halfway shows it again next time")
        record.markSeen()
        XCTAssertFalse(record.shouldShowTour(access: .granted))
    }

    func testSomeoneUpdatingFromAnOlderVersionSkipsIt() {
        XCTAssertFalse(record().shouldShowTour(access: .granted))
        XCTAssertFalse(record().shouldShowTour(access: .denied))
    }

    func testOnceTheTourHasStartedAnsweringAccessDoesNotHideItOnRelaunch() {
        let record = record()
        XCTAssertTrue(record.shouldShowTour(access: .notDetermined))
        XCTAssertTrue(record.shouldShowTour(access: .granted), "Granted access mid-tour, then quit before the end")
    }

    func testStepsRunInOrder() {
        XCTAssertEqual(OnboardingStep.allCases.first, .welcome)
        XCTAssertEqual(OnboardingStep.welcome.next, .calendars)
        XCTAssertTrue(OnboardingStep.done.isLast)
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.done.continueTitle, "Open Orbit")
    }

    func testStartingWithoutAskingLeavesAccessForTheTour() async {
        let store = FakeEventStore()
        store.access = .notDetermined
        let state = AppState(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!), eventService: store)
        await state.start(askForAccess: false)
        XCTAssertEqual(state.access, .notDetermined)
    }
}

@MainActor
final class MenuBarMockTests: XCTestCase {

    func testEveryStyleShowsWhatItReallyWould() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "OrbitMock-\(UUID().uuidString)")!)
        let now = TestSupport.date(2026, 11, 5, 11, 8)
        let title = { (preset: MenuBarPreset) -> String in
            preferences.menuBarFormat.preset = preset
            return MenuBarMock.sampleTitle(preferences, now: now, calendar: TestSupport.calendar())
        }
        XCTAssertEqual(title(.agenda), "Design review in 12m")
        XCTAssertTrue(title(.info).hasSuffix("Design review in 12m"))
        XCTAssertTrue(title(.info).contains("Nov 5"))
        XCTAssertFalse(title(.classic).contains("Design review"))
        XCTAssertFalse(title(.minimal).contains("Nov"))
        XCTAssertEqual(title(.icon), "")
    }

    func testAShortLeadTimeStillShowsTheSampleMeeting() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "OrbitMock-\(UUID().uuidString)")!)
        preferences.nextEventLeadMinutes = 5
        preferences.menuBarFormat.preset = .agenda
        XCTAssertEqual(MenuBarMock.sampleTitle(preferences, now: TestSupport.date(2026, 11, 5, 9), calendar: TestSupport.calendar()), "Design review in 12m")
    }
}
