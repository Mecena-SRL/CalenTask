import Foundation
import SwiftData

/// Chi è disponibile per la produzione: persona della troupe, attrezzatura o
/// fornitore. Riusabile tra TUTTI i progetti dello spazio (il vantaggio su
/// Yamdu, D53). Mappa sulla futura tabella Supabase `contacts`.
@Model
final class Contact {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var name: String = ""
    /// Ruolo abituale ("DOP", "Fonico", "Runner") o categoria attrezzo.
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var notes: String = ""
    var kindRaw: String = ""
    /// Il legame col contatto di sistema (`CNContact.identifier`, V5/D72):
    /// nil = contatto solo nostro; valorizzato = importato/collegato ad
    /// Apple Contacts, aggiornabile da lì.
    var contactIdentifier: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var kind: ContactKind {
        get { ContactKind(rawValue: kindRaw) ?? .person }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        kind: ContactKind = .person,
        role: String = "",
        phone: String = "",
        email: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.kindRaw = kind.rawValue
        self.role = role
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

enum ContactKind: String, Codable, CaseIterable, Identifiable {
    case person, equipment, supplier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: "Troupe"
        case .equipment: "Attrezzatura"
        case .supplier: "Fornitore"
        }
    }

    var systemImage: String {
        switch self {
        case .person: "person"
        case .equipment: "camera"
        case .supplier: "shippingbox"
        }
    }
}
