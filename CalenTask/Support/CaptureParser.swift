import Foundation

/// Parsing del quick add (S4/D60): `!priorità` e `/progetto` scritti nel
/// testo, più il token attivo per l'autocomplete live di #etichette e
/// /progetti. Le date naturali restano a NaturalDateParser.
enum CaptureParser {
    struct Result: Equatable {
        var title: String
        var priority: TaskPriority?
        var projectQuery: String?
    }

    /// Estrae `!priorità` e `/progetto`; il titolo torna ripulito dai token.
    static func parse(_ text: String) -> Result {
        var result = Result(title: text)
        var words: [Substring] = []
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            if word.hasPrefix("!"), let priority = priority(from: word.dropFirst()) {
                result.priority = priority
            } else if word.hasPrefix("/"), word.count > 1 {
                result.projectQuery = String(word.dropFirst())
            } else {
                words.append(word)
            }
        }
        result.title = words.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return result
    }

    private static func priority(from raw: Substring) -> TaskPriority? {
        switch raw.lowercased() {
        case "urgente", "4": .urgent
        case "alta", "3": .high
        case "media", "normale", "2": .normal
        case "bassa", "1": .low
        default: nil
        }
    }

    /// L'ultimo token in scrittura, se è un'#etichetta o un /progetto
    /// (niente spazio finale = lo stai ancora scrivendo).
    static func activeToken(in text: String) -> (prefix: Character, query: String)? {
        guard !text.isEmpty, !text.hasSuffix(" ") else { return nil }
        guard let last = text.split(separator: " ").last,
              let first = last.first, first == "#" || first == "/"
        else { return nil }
        return (first, String(last.dropFirst()))
    }

    /// Sostituisce il token attivo col completamento scelto (per le #etichette).
    static func completing(
        _ text: String, token: (prefix: Character, query: String), with name: String
    ) -> String {
        guard let last = text.split(separator: " ").last else { return text }
        return String(text.dropLast(last.count)) + "\(token.prefix)\(name) "
    }

    /// Rimuove il token attivo dal testo (per i /progetti, che diventano chip).
    static func removingActiveToken(_ text: String) -> String {
        guard let last = text.split(separator: " ").last else { return text }
        return String(text.dropLast(last.count))
    }
}
