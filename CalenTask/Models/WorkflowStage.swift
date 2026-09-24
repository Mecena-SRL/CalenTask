import Foundation
import SwiftData

// Maps to future Supabase table `workflow_stages` (D29).
// The custom pipeline of a project: ordered, colored stages a task moves
// through (Preventivo → Conferma → … → Archivio). ID-based edge like
// TaskDependency: tasks point at a stage via `stageID`.
@Model
final class WorkflowStage {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var projectID: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var colorHex: String = ""
    /// Terminal stages ("Archivio", "Consegnato") count as pipeline-complete.
    var isTerminal: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        projectID: UUID,
        name: String,
        order: Int,
        colorHex: String = "#0E7490",
        isTerminal: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.name = name
        self.order = order
        self.colorHex = colorHex
        self.isTerminal = isTerminal
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Default palette for pipeline stages, monday-style vivid.
    static let palette = [
        "#2563EB", "#7C3AED", "#DB2777", "#DC2626", "#D97706", "#CA8A04",
        "#16A34A", "#059669", "#0E7490", "#475569", "#9333EA", "#0284C7",
    ]

    static func defaultColor(forOrder order: Int) -> String {
        palette[order % palette.count]
    }
}
