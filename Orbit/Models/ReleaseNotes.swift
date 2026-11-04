import Foundation

/// Release notes from GitHub, turned into lines the update dialog can draw.
enum ReleaseNotes {

    enum Line: Equatable {
        case heading(String)
        case bullet(AttributedString)
        case paragraph(AttributedString)
    }

    /// Starts at the "What's new" heading when there is one, skipping the install instructions above it,
    /// which the dialog's Download button already covers. Bold, italics, code and links are kept.
    static func lines(from markdown: String) -> [Line] {
        var rows = markdown.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if let start = rows.firstIndex(where: { $0.hasPrefix("#") && $0.lowercased().contains("what's new") }) {
            rows = Array(rows[start...])
        }
        return rows.compactMap { row in
            if row.isEmpty { return nil }
            if row.hasPrefix("#") {
                return .heading(row.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
            }
            for marker in ["- ", "* ", "• "] where row.hasPrefix(marker) {
                return .bullet(inline(String(row.dropFirst(marker.count))))
            }
            return .paragraph(inline(row))
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
