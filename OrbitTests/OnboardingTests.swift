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
