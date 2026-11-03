import AppKit
import SwiftUI

/// Text styles used in the calendar, scaled by the "Text size" setting.
enum OrbitTextStyle {
    case caption, callout, subheadline, headline, body, title

    var size: CGFloat {
        switch self {
        case .caption: 10
        case .subheadline: 11
        case .callout: 12
        case .body, .headline: 13
        case .title: 16
        }
    }

    var weight: Font.Weight {
        self == .headline || self == .title ? .semibold : .regular
    }
}

extension EnvironmentValues {
    @Entry var textScale: CGFloat = 1
}

private struct ScaledFont: ViewModifier {

    @Environment(\.textScale) private var scale
    let style: OrbitTextStyle
    let weight: Font.Weight?
    let monospacedDigit: Bool

    func body(content: Content) -> some View {
        let font = Font.system(size: style.size * scale, weight: weight ?? style.weight)
        content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

extension View {
    func orbitFont(_ style: OrbitTextStyle, weight: Font.Weight? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFont(style: style, weight: weight, monospacedDigit: monospacedDigit))
    }
}

extension EventColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension NSColor {
    /// The teal from Orbit's icon, a shade deeper in light mode so white text on it stays readable.
    static let orbitTeal = NSColor(name: "orbitTeal") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.10, green: 0.69, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 0.05, green: 0.60, blue: 0.71, alpha: 1)
    }
}

extension Color {
    /// Orbit's accent everywhere, instead of the system accent color.
    static let orbitTeal = Color(nsColor: .orbitTeal)
}
