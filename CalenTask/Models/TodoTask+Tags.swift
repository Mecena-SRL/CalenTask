import Foundation

/// #hashtag support (D21): labels typed inline in title or notes.
/// A tag is a single `#word` (letters, numbers, _ , -), case-insensitive.
enum HashtagParser {
    private static let pattern = try! Regex(#"#([\p{L}\p{N}_\-]+)"#)

    /// Ordered, deduplicated, lowercased tag names found in the text.
    static func tagNames(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for match in text.matches(of: pattern) {
            guard let range = match[1].range else { continue }
            let name = String(text[range]).lowercased()
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}

extension TodoTask {
    /// Tag names parsed from the live text — title first, then notes (D21).
    var parsedTagNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in HashtagParser.tagNames(in: title) + HashtagParser.tagNames(in: notes) {
            if seen.insert(name).inserted { result.append(name) }
        }
        return result
    }

    /// Live assigned tags, ordered like the text mentions them (extras after).
    var orderedTags: [Tag] {
        let live = tags.filter { $0.deletedAt == nil }
        let parsed = parsedTagNames
        return live.sorted {
            let l = parsed.firstIndex(of: $0.name) ?? Int.max
            let r = parsed.firstIndex(of: $1.name) ?? Int.max
            return l == r ? $0.name < $1.name : l < r
        }
    }

    /// The card's accent: the color of the FIRST label found — title, then
    /// notes, then any assigned tag (D21). Nil ⇒ no label, no tint.
    var accentTagColorHex: String? {
        let live = tags.filter { $0.deletedAt == nil }
        guard !live.isEmpty else { return nil }
        for name in parsedTagNames {
            if let tag = live.first(where: { $0.name == name }) {
                return tag.colorHex
            }
        }
        return live.first?.colorHex
    }
}
