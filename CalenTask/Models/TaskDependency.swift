import Foundation
import SwiftData

// Maps to future Supabase table `task_dependencies` — edges for graph/Gantt views.
@Model
final class TaskDependency {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var fromTaskID: UUID = UUID()
    var toTaskID: UUID = UUID()
    var typeRaw: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var type: DependencyType {
        get { DependencyType(rawValue: typeRaw) ?? .finishToStart }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        fromTaskID: UUID,
        toTaskID: UUID,
        type: DependencyType = .finishToStart,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.fromTaskID = fromTaskID
        self.toTaskID = toTaskID
        self.typeRaw = type.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
