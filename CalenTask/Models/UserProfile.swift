import Foundation
import SwiftData

// Local mirror of the future Supabase auth user (`profiles` table).
@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var avatarURL: URL?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// Vero solo per il profilo "me" auto-generato al primo avvio locale
    /// (V10, audit account A1): distingue il placeholder di dispositivo da
    /// una persona invitata/aggiunta a mano, così la dedupe multi-dispositivo
    /// non fonde più due compagni di team che condividono un nome.
    var isLocalSeed: Bool = false

    init(
        id: UUID = UUID(), name: String, email: String, avatarURL: URL? = nil,
        createdAt: Date = .now, isLocalSeed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isLocalSeed = isLocalSeed
    }
}
