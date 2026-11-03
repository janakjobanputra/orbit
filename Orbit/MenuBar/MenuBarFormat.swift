import Foundation

enum MenuBarToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case date, time, nextEvent, weekNumber

    var id: String { rawValue }

    var label: String {
        switch self {
        case .date: "Date"
        case .time: "Time"
        case .nextEvent: "Next Event"
        case .weekNumber: "Week Number"
        }
    }

    var symbol: String {
        switch self {
        case .date: "calendar"
        case .time: "clock"
        case .nextEvent: "calendar.badge.clock"
        case .weekNumber: "number"
        }
    }
}

enum MenuBarPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, minimal, agenda, info, custom

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    /// The tokens a preset shows; `nil` for custom, which uses the user's own list.
    var tokens: [MenuBarToken]? {
        switch self {
        case .classic: [.date, .time]
        case .minimal: [.time]
        case .agenda: [.nextEvent]
        case .info: [.date, .time, .nextEvent]
        case .custom: nil
        }
    }
}

enum SeparatorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case bar, dot, dash, space

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bar: "|"
        case .dot: "·"
        case .dash: "—"
        case .space: "Space"
        }
    }

    var joiner: String {
        switch self {
        case .bar: " | "
        case .dot: " · "
        case .dash: " — "
        case .space: "  "
        }
    }
}

struct MenuBarFormat: Codable, Equatable, Sendable {

    static let defaultDatePattern = "EEE, MMM d"
    static let defaultTimePattern = "h:mm"

    /// Date patterns offered in the Settings dropdown.
    static let datePatterns = [
        "EEE, MMM d",
        "EEE d MMM",
        "MMM d",
        "d MMM",
        "EEEE",
        "EEEE, MMM d",
        "EEE, MMM d, yyyy",
    ]

    var preset: MenuBarPreset = .classic
    var customTokens: [MenuBarToken] = [.date, .time]
    var datePattern = defaultDatePattern
    var timePattern = defaultTimePattern
    var separator: SeparatorStyle = .dot

    var tokens: [MenuBarToken] { preset.tokens ?? customTokens }

    var uses24HourTime: Bool { timePattern.contains("H") }

    /// Switches the time pattern between 12- and 24-hour clocks, keeping the rest of it.
    mutating func setUses24HourTime(_ enabled: Bool) {
        if enabled {
            timePattern = timePattern
                .replacingOccurrences(of: "h", with: "H")
                .replacingOccurrences(of: " a", with: "")
                .replacingOccurrences(of: "a", with: "")
        } else {
            timePattern = timePattern.replacingOccurrences(of: "H", with: "h")
        }
    }
}
