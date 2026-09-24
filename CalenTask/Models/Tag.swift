import Foundation
import SwiftData

// Maps to future Supabase table `tags` (workspace-scoped labels, m2m with tasks).
@Model
final class Tag {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    // CloudKit esige relazioni OPZIONALI (v7-fix): storage optional con
    // `originalName`, API non-optional via bridge — vedi TodoTask.
    @Relationship(originalName: "tasks")
    var tasksStorage: [TodoTask]? = []

    var tasks: [TodoTask] {
        get { tasksStorage ?? [] }
        set { tasksStorage = newValue }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        colorHex: String = "#64748B",
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.tasksStorage = []
    }
}
