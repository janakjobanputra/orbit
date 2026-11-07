import XCTest
@testable import Orbit

private actor RecordingSender: ReportSending {
    var sent: [(path: String, body: Data)] = []
    var failing = false
    func setFailing(_ value: Bool) { failing = value }
    func send(_ body: Data, to path: String) async throws {
        if failing { throw WorkerReportSender.Rejected() }
        sent.append((path, body))
    }
}

@MainActor
final class TelemetryTests: XCTestCase {

    private let environment = ReportEnvironment(version: "1.1.5", build: "202611061134", osMajor: "15", arch: "arm64")

    private func make(configure: @MainActor (FakeEventStore, Preferences) -> Void = { _, _ in }) async -> (Telemetry, RecordingSender, TestClock, AppState) {
        let (state, _, clock) = await StateFixture.make(configure: configure)
        let sender = RecordingSender()
        let defaults = UserDefaults(suiteName: "OrbitTelemetry-\(UUID().uuidString)")!
        let telemetry = Telemetry(appState: state, sender: sender, defaults: defaults, environment: environment) { clock.now }
        return (telemetry, sender, clock, state)
    }

    func testDefaultsAreUsageOffAndCrashReportsOn() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: "OrbitTelemetry-\(UUID().uuidString)")!)
        XCTAssertFalse(preferences.shareUsageStats)
        XCTAssertTrue(preferences.sendCrashReports)
    }

    func testNoUsageReportUnlessYouOptIn() async {
        let (telemetry, sender, _, _) = await make()
        await telemetry.sendUsageIfDue()
        let sent = await sender.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func testUsageGoesOnceADay() async {
        let (telemetry, sender, clock, _) = await make { _, preferences in preferences.shareUsageStats = true }
        await telemetry.sendUsageIfDue()
        await telemetry.sendUsageIfDue()
        var sent = await sender.sent
        XCTAssertEqual(sent.map(\.path), ["api/usage"])
        clock.now = clock.now.addingTimeInterval(24 * 3600)
        await telemetry.sendUsageIfDue()
        sent = await sender.sent
        XCTAssertEqual(sent.count, 2)
    }

    func testAFailedSendTriesAgain() async {
        let (telemetry, sender, _, _) = await make { _, preferences in preferences.shareUsageStats = true }
        await sender.setFailing(true)
        await telemetry.sendUsageIfDue()
        await sender.setFailing(false)
        await telemetry.sendUsageIfDue()
        let sent = await sender.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testUsageReportHoldsOnlyOptionsAndBuckets() async throws {
        let (telemetry, sender, _, _) = await make { store, preferences in
            preferences.shareUsageStats = true
            store.calendarList = [StateFixture.calendarInfo("Private therapy calendar")]
            store.add(TestSupport.event("Secret meeting", start: StateFixture.now, minutes: 30))
            preferences.ignoredTitleKeywords = "secret keyword"
        }
        await telemetry.sendUsageIfDue()
        let sent = await sender.sent
        let body = try XCTUnwrap(sent.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["version", "os", "arch", "eventsView", "menuBarStyle", "textSize", "eventDensity", "calendars"])
        XCTAssertEqual(json["version"], "1.1.5")
        XCTAssertEqual(json["os"], "15")
        XCTAssertEqual(json["calendars"], "1-3")
        let text = String(decoding: body, as: UTF8.self).lowercased()
        for secret in ["therapy", "secret"] { XCTAssertFalse(text.contains(secret)) }
    }

    /// The values the Worker accepts are in site-worker.js; a mismatch would silently lose every report.
    func testReportValuesAreOnesTheWorkerAccepts() throws {
        let worker = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "site-worker.js"), encoding: .utf8)
        func listed(_ value: String) -> Bool { worker.contains("\"\(value)\"") }
        for value in EventsView.allCases.map(\.rawValue) + MenuBarPreset.allCases.map(\.rawValue) + TextSize.allCases.map(\.rawValue) + Density.allCases.map(\.rawValue) {
            XCTAssertTrue(listed(value), "\(value) isn't in the Worker's list")
        }
        for count in [0, 2, 5, 40] { XCTAssertTrue(listed(UsageReport.bucket(count))) }
    }

    func testCrashReportsRespectTheSwitch() async {
        let crash = CrashReport(version: "1.1.5", build: "1", os: "15", arch: "arm64", signal: 11, callStack: "{}")
        let (telemetry, sender, _, state) = await make()
        await telemetry.send([crash])
        var sent = await sender.sent
        XCTAssertEqual(sent.map(\.path), ["api/crash"], "On by default")

        state.preferences.sendCrashReports = false
        await telemetry.send([crash])
        sent = await sender.sent
        XCTAssertEqual(sent.count, 1)
    }

    func testOSVersionIsReducedToItsMajorNumber() {
        XCTAssertEqual(CrashDiagnostics.normalizedOS("macOS 15.4.1 (24E263)"), "15")
        XCTAssertEqual(CrashDiagnostics.normalizedOS("26.0"), "26")
        XCTAssertEqual(CrashDiagnostics.normalizedOS("unknown"), "0")
    }
}
