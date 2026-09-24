import Foundation
import SwiftData

/// Convocazione: un contatto (persona o attrezzo) su un'attività — tipicamente
/// un giorno di ripresa. Edge per ID (stile CustomFieldValue) così i conflitti
/// si calcolano tra progetti e spazi diversi. Tabella Supabase `crew_assignments`.
@Model
final class CrewAssignment {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var contactID: UUID = UUID()
    /// L'attività convocante (il giorno di ripresa, o qualunque task).
    var taskID: UUID = UUID()
    /// Ruolo per QUESTA convocazione, se diverso dall'abituale.
    var roleOverride: String = ""
    /// Orario di convocazione individuale (nil ⇒ il call time del giorno).
    var callTime: Date?
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        contactID: UUID,
        taskID: UUID,
        roleOverride: String = "",
        callTime: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.contactID = contactID
        self.taskID = taskID
        self.roleOverride = roleOverride
        self.callTime = callTime
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
