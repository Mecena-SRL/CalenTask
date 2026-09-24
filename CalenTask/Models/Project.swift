import Foundation
import SwiftData

// Maps to future Supabase table `projects`.
@Model
final class Project {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var statusRaw: String = ""
    var colorHex: String = ""
    var startDate: Date?
    var dueDate: Date?
    var sortOrder: Int = 0
    /// Preferito (V6, D75): sempre sott'occhio in cima a sidebar e Sfoglia.
    var isFavorite: Bool = false
    /// V7 (F39): la produzione video (Scene/PDL/ODG) è opt-in per progetto.
    var productionEnabled: Bool = false
    var createdByID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    // CloudKit esige relazioni OPZIONALI (v7-fix): storage optional con
    // `originalName`, API non-optional via bridge — vedi TodoTask.
    @Relationship(deleteRule: .cascade, originalName: "tasks",
                  inverse: \TodoTask.project)
    var tasksStorage: [TodoTask]? = []

    var tasks: [TodoTask] {
        get { tasksStorage ?? [] }
        set { tasksStorage = newValue }
    }

    /// V8 (G13) — i progetti hanno figli: gerarchia fino a 5 generazioni
    /// (il limite vive nella UI, vedi `canBecomeParent`).
    var parentProject: Project?

    @Relationship(inverse: \Project.parentProject)
    var subprojectsStorage: [Project]? = []

    var subprojects: [Project] {
        get { subprojectsStorage ?? [] }
        set { subprojectsStorage = newValue }
    }

    /// I figli vivi, ordinati.
    var liveSubprojects: [Project] {
        subprojects
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Quante generazioni sopra di me (0 = radice).
    var generation: Int {
        var depth = 0
        var node = parentProject
        while let parent = node, depth < 10 {
            depth += 1
            node = parent.parentProject
        }
        return depth
    }

    /// G13 — massimo 5 generazioni: può fare da padre chi sta entro la 4ª,
    /// e mai un mio discendente (niente cicli).
    func canBecomeParent(of child: Project) -> Bool {
        guard id != child.id, generation < 4 else { return false }
        var node: Project? = self
        while let current = node {
            if current.id == child.id { return false }
            node = current.parentProject
        }
        return true
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Top-level phase containers (tasks of kind .phase without a parent), ordered.
    /// Phases ARE tasks since v2 — see Progettazione/04, D5.
    var phaseTasks: [TodoTask] {
        tasks
            .filter { $0.deletedAt == nil && $0.isPhase && $0.parentTask == nil && !$0.isTemplate }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Live non-phase tasks at the project root (no parent), ordered.
    var unphasedTasks: [TodoTask] {
        tasks
            .filter { $0.deletedAt == nil && !$0.isPhase && $0.parentTask == nil && !$0.isTemplate }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        notes: String = "",
        status: ProjectStatus = .active,
        colorHex: String = "#0E7490",
        startDate: Date? = nil,
        dueDate: Date? = nil,
        sortOrder: Int = 0,
        createdByID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.notes = notes
        self.statusRaw = status.rawValue
        self.colorHex = colorHex
        self.startDate = startDate
        self.dueDate = dueDate
        self.sortOrder = sortOrder
        self.createdByID = createdByID
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.tasksStorage = []
    }
}
