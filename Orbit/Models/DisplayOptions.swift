import CoreGraphics
import Foundation

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum EventDotsStyle: String, CaseIterable, Identifiable, Sendable {
    case off, single, colors

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .single: "Single dot"
        case .colors: "Calendar colors"
        }
    }

    /// The styles offered once dots are switched on.
    static let onStyles: [Self] = [.single, .colors]
}

enum WeekStart: Int, CaseIterable, Identifiable, Sendable {
    case sunday = 1, monday = 2

    var id: Int { rawValue }
    var label: String { self == .sunday ? "Sun" : "Mon" }
}

enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case small, standard, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "XL"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.12
        case .extraLarge: 1.25
        }
    }
}

enum Density: String, CaseIterable, Identifiable, Sendable {
    case compact, cozy, airy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var dayCellSize: CGFloat {
        switch self {
        case .compact: 26
        case .cozy: 30
        case .airy: 34
        }
    }

    var gridSpacing: CGFloat {
        switch self {
        case .compact: 2
        case .cozy: 5
        case .airy: 8
        }
    }

    var eventSpacing: CGFloat {
        switch self {
        case .compact: 6
        case .cozy: 9
        case .airy: 12
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .compact: 14
        case .cozy: 18
        case .airy: 24
        }
    }
}

enum MapsProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, google

    var id: String { rawValue }
    var label: String { self == .apple ? "Apple Maps" : "Google Maps" }

    func url(for location: String) -> URL? {
        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components: URLComponents
        switch self {
        case .apple:
            components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .google:
            components = URLComponents(string: "https://www.google.com/maps/search/")!
            components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        }
        return components.url
    }
}

/// A video service the user added so its links get a Join button.
struct CustomVideoService: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var host: String

    /// Accepts a full link or a bare domain and returns the lowercase host without `www.`.
    static func normalizedHost(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URL(string: candidate)?.host, host.contains(".") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum TitleFilter {

    static func keywords(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isIgnored(_ title: String, keywords: [String]) -> Bool {
        keywords.contains { title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
