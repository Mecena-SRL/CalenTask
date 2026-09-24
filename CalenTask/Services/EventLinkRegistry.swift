import Foundation

/// #1 — Collegamenti evento ↔ task PROPRI di questo dispositivo.
///
/// `EKEvent.eventIdentifier` è locale al dispositivo, ma la task che lo
/// conteneva viaggia su iCloud: il Mac leggeva l'id dell'iPhone come "evento
/// sparito" e cancellava la task (e viceversa), e ogni dispositivo importava
/// la stessa riunione come task nuova. Il registro vive in UserDefaults, che
/// NON si sincronizza: ogni dispositivo decide solo sui propri collegamenti.
struct EventLinkRegistry {
    static let storageKey = "calendarSync.localLinks.v1"

    /// eventIdentifier locale → id della task.
    private(set) var links: [String: UUID]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        links = raw.compactMapValues(UUID.init(uuidString:))
    }

    func taskID(forEvent identifier: String) -> UUID? { links[identifier] }

    func eventIdentifier(forTask taskID: UUID) -> String? {
        links.first { $0.value == taskID }?.key
    }

    func isLinkedHere(_ taskID: UUID) -> Bool { links.values.contains(taskID) }

    /// Una task ha al massimo un evento locale: il collegamento nuovo
    /// sostituisce quello vecchio.
    mutating func link(event identifier: String, to taskID: UUID) {
        guard links[identifier] != taskID else { return }
        for (key, value) in links where value == taskID { links[key] = nil }
        links[identifier] = taskID
        save()
    }

    mutating func unlink(event identifier: String) {
        guard links.removeValue(forKey: identifier) != nil else { return }
        save()
    }

    private func save() {
        defaults.set(links.mapValues(\.uuidString), forKey: Self.storageKey)
    }
}
