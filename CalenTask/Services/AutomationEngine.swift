import Foundation
import SwiftData

/// Automazioni no-code (D31): regole trigger → azioni agganciate alle
/// transizioni di pipeline e stato, dentro il funnel delle mutazioni.
/// Le azioni non rilanciano trigger (niente cascate involontarie).
@MainActor
enum AutomationEngine {
    /// Hook: a task entered a workflow stage (D29 → D31).
    static func taskEnteredStage(_ task: TodoTask, stage: WorkflowStage, in context: ModelContext) {
        run(task: task, in: context) { rule in
            rule.triggerType == .enteredStage && rule.triggerStageID == stage.id
        }
    }

    /// Hook: a task changed plain status (incl. completion → .done).
    static func taskChangedStatus(_ task: TodoTask, in context: ModelContext) {
        let status = task.status
        run(task: task, in: context) { rule in
            rule.triggerType == .statusChanged && rule.triggerStatus == status
        }
    }

    // MARK: Execution

    private static func run(
        task: TodoTask, in context: ModelContext, matching: (AutomationRule) -> Bool
    ) {
        guard let projectID = task.project?.id, !task.isTemplate else { return }
        let rules: [AutomationRule]
        do {
            rules = try context.fetch(FetchDescriptor<AutomationRule>(
                predicate: #Predicate { $0.deletedAt == nil && $0.isEnabled }
            ))
        } catch {
            assertionFailure("Automation fetch failed: \(error)")
            return
        }
        for rule in rules where rule.projectID == projectID && matching(rule) {
            execute(rule, for: task, in: context)
        }
    }

    private static func execute(_ rule: AutomationRule, for task: TodoTask, in context: ModelContext) {
        // 1. Create a follow-up task.
        if let titleTemplate = rule.createTaskTitle,
           !titleTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            let title = titleTemplate.replacingOccurrences(of: "{task}", with: task.title)
            let followUp = TodoTask(
                workspaceID: task.workspaceID,
                title: title,
                assigneeID: rule.createTaskAssigneeID,
                sortOrder: task.sortOrder + 1,
                createdByID: task.createdByID
            )
            if let offset = rule.createTaskDueOffsetDays {
                followUp.dueAt = Calendar.current.date(
                    byAdding: .day, value: offset, to: .now.startOfDay
                )
            }
            followUp.source = .automation
            context.insert(followUp)
            followUp.project = task.project
            followUp.parentTask = task.parentTask
            NotificationService.shared.sync(task: followUp)
        }

        // 2. Re-assign the triggering task.
        if let assignee = rule.assignToID {
            task.assigneeID = assignee
            task.updatedAt = .now
        }

        // 3. Notify a person (local notification on this device, v1).
        if let notifyID = rule.notifyUserID {
            let person = try? context.fetch(FetchDescriptor<UserProfile>(
                predicate: #Predicate { $0.id == notifyID }
            )).first
            NotificationService.shared.postAutomationNotice(
                title: "Automazione · \(rule.name)",
                body: "\(person?.name ?? "Team"): «\(task.title)»"
            )
        }
    }
}
