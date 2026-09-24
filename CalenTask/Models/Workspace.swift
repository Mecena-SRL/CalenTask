import Foundation
import SwiftData

// Maps to future Supabase table `workspaces`.
// Seeded: solo "Personale" (isPersonal). Gli altri spazi li crea l'utente (D49).
@Model
final class Workspace {
    var id: UUID = UUID()
    var name: String = ""
    var isPersonal: Bool = false
    var colorHex: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        isPersonal: Bool = false,
        colorHex: String = "#0E7490",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.isPersonal = isPersonal
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
