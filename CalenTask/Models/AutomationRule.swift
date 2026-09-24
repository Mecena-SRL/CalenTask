import Foundation
import SwiftData

// Maps to future Supabase table `automation_rules` (D31).
// One rule = a trigger + a flat bundle of actions. The canonical example:
// quando entra in "Approvato" → crea "Preparare export", assegna Ivan,
// scadenza +2 giorni, notifica Eleonora.
@Model
final class AutomationRule {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var projectID: UUID = UUID()
    var name: String = ""
    var isEnabled: Bool = false

    // Trigger: "enteredStage" (pipeline) or "statusChanged" (stato base).
    var triggerTypeRaw: String = ""
    var triggerStageID: UUID?
    var triggerStatusRaw: String?

    // Actions — nil/empty means "skip this action".
    /// Title of the task to create; "{task}" expands to the trigger task's title.
    var createTaskTitle: String?
    var createTaskAssigneeID: UUID?
    var createTaskDueOffsetDays: Int?
    /// Re-assign the triggering task.
    var assignToID: UUID?
    /// Post a local notification addressed to this person.
    var notifyUserID: UUID?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    enum TriggerType: String, CaseIterable, Identifiable {
        case enteredStage, statusChanged

        var id: String { rawValue }

        var label: String {
            switch self {
            case .enteredStage: "Entra nello stage"
            case .statusChanged: "Passa allo stato"
            }
        }
    }

    var triggerType: TriggerType {
        get { TriggerType(rawValue: triggerTypeRaw) ?? .enteredStage }
        set { triggerTypeRaw = newValue.rawValue }
    }

    var triggerStatus: TaskStatus? {
        get { triggerStatusRaw.flatMap(TaskStatus.init(rawValue:)) }
        set { triggerStatusRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        projectID: UUID,
        name: String,
        triggerType: TriggerType = .enteredStage,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.name = name
        self.isEnabled = true
        self.triggerTypeRaw = triggerType.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
