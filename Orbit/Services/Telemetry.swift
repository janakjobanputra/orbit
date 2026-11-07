import Foundation
import MetricKit

/// The once-a-day usage report, sent only if you turn it on. Options only, in broad buckets, with no ID:
/// the server just counts how many identical reports it gets each day.
struct UsageReport: Codable, Equatable {
    var version: String
    var os: String
    var arch: String
    var eventsView: String
    var menuBarStyle: String
    var textSize: String
    var eventDensity: String
    var calendars: String

    @MainActor
    init(preferences: Preferences, calendarCount: Int, environment: ReportEnvironment = .current) {
        version = environment.version
        os = environment.osMajor
        arch = environment.arch
        eventsView = preferences.eventsView.rawValue
        menuBarStyle = preferences.menuBarFormat.preset.rawValue
        textSize = preferences.textSize.rawValue
        eventDensity = preferences.eventDensity.rawValue
        calendars = Self.bucket(calendarCount)
    }

    static func bucket(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1...3: "1-3"
        case 4...9: "4-9"
        default: "10+"
        }
    }

    /// As it's sent, for Settings to show.
    var readableJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// Sent after a crash, unless you turn it off. The call stack is binary names and offsets from macOS's own crash
/// diagnostics. Deliberately leaves out the crash's message text, which could quote something from your calendar.
struct CrashReport: Codable, Equatable, Sendable {
    var version: String
    var build: String
    var os: String
    var arch: String
    var exceptionType: Int?
    var exceptionCode: Int?
    var signal: Int?
    var callStack: String
}

struct ReportEnvironment: Sendable {
    var version: String
    var build: String
    var osMajor: String
    var arch: String

    static var current: ReportEnvironment {
        let info = Bundle.main.infoDictionary
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return ReportEnvironment(
            version: info?["CFBundleShortVersionString"] as? String ?? "0",
            build: info?["CFBundleVersion"] as? String ?? "0",
            osMajor: String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
            arch: arch
        )
    }
}

protocol ReportSending: Sendable {
    func send(_ body: Data, to path: String) async throws
}

/// Posts to the same Cloudflare Worker that serves try-orbit.app.
struct WorkerReportSender: ReportSending {

    static let base = URL(string: "https://try-orbit.app")!

    struct Rejected: Error {}

    func send(_ body: Data, to path: String) async throws {
        var request = URLRequest(url: Self.base.appending(path: path), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw Rejected() }
    }
}

/// Decides when reports go out, always going by the current settings.
@MainActor
final class Telemetry {

    private static let lastUsageDayKey = "lastUsageReportDay"

    private let appState: AppState
    private let sender: any ReportSending
    private let defaults: UserDefaults
    private let environment: ReportEnvironment
    private let clock: () -> Date

    init(
        appState: AppState,
        sender: any ReportSending = WorkerReportSender(),
        defaults: UserDefaults = .standard,
        environment: ReportEnvironment = .current,
        clock: @escaping () -> Date = Date.init
    ) {
        self.appState = appState
        self.sender = sender
        self.defaults = defaults
        self.environment = environment
        self.clock = clock
    }

    /// At most once a calendar day. A failed send tries again next time, and nothing is ever queued up.
    func sendUsageIfDue() async {
        guard appState.preferences.shareUsageStats, appState.access == .granted else { return }
        let day = clock().formatted(.iso8601.year().month().day())
        guard defaults.string(forKey: Self.lastUsageDayKey) != day else { return }
        let report = UsageReport(preferences: appState.preferences, calendarCount: appState.calendars.count, environment: environment)
        guard let body = try? JSONEncoder().encode(report) else { return }
        do {
            try await sender.send(body, to: "api/usage")
            defaults.set(day, forKey: Self.lastUsageDayKey)
        } catch {}
    }

    func send(_ crashes: [CrashReport]) async {
        guard appState.preferences.sendCrashReports else { return }
        for crash in crashes {
            guard let body = try? JSONEncoder().encode(crash) else { continue }
            try? await sender.send(body, to: "api/crash")
        }
    }
}

/// macOS hands over crash diagnostics through MetricKit, usually the next time the app runs after a crash.
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    private let deliver: @MainActor @Sendable ([CrashReport]) -> Void

    init(deliver: @escaping @MainActor @Sendable ([CrashReport]) -> Void) {
        self.deliver = deliver
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }.compactMap(Self.report)
        guard !crashes.isEmpty else { return }
        let deliver = deliver
        Task { @MainActor in deliver(crashes) }
    }

    private static func report(_ crash: MXCrashDiagnostic) -> CrashReport? {
        guard let callStack = String(data: crash.callStackTree.jsonRepresentation(), encoding: .utf8) else { return nil }
        let metaData = crash.metaData
        return CrashReport(
            // The version running now, which is the crashed one unless Orbit has just updated. `build` says for certain.
            version: ReportEnvironment.current.version,
            build: metaData.applicationBuildVersion,
            os: normalizedOS(metaData.osVersion),
            arch: ReportEnvironment.current.arch,
            exceptionType: crash.exceptionType?.intValue,
            exceptionCode: crash.exceptionCode?.intValue,
            signal: crash.signal?.intValue,
            callStack: callStack
        )
    }

    /// MetricKit says "macOS 15.4.1 (24E263)"; reports only carry "15".
    static func normalizedOS(_ text: String) -> String {
        text.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.flatMap { $0.split(separator: ".").first }.map(String.init) ?? "0"
    }
}
