import Foundation
import SwiftData

@MainActor
enum TemplateService {
    /// Creates a project from a template: each template phase becomes a
    /// top-level task of kind .phase, lavorazioni become its children (D5).
    @discardableResult
    static func apply(
        _ template: ProjectTemplate,
        projectName: String,
        colorHex: String? = nil,
        workspaceID: UUID,
        createdBy: UUID,
        in context: ModelContext
    ) throws -> Project {
        let project = Project(
            workspaceID: workspaceID,
            name: projectName,
            colorHex: colorHex ?? template.suggestedColorHex,
            createdByID: createdBy
        )
        context.insert(project)

        // Pipeline (D29): the template's stages become the project workflow.
        for (stageIndex, stageName) in template.stages.enumerated() {
            context.insert(WorkflowStage(
                workspaceID: workspaceID,
                projectID: project.id,
                name: stageName,
                order: stageIndex,
                colorHex: WorkflowStage.defaultColor(forOrder: stageIndex),
                isTerminal: stageIndex == template.stages.count - 1
            ))
        }

        for (phaseIndex, phaseTemplate) in template.phases.enumerated() {
            let phaseTask = TodoTask(
                workspaceID: workspaceID,
                title: phaseTemplate.name,
                kind: .phase,
                sortOrder: phaseIndex,
                createdByID: createdBy
            )
            context.insert(phaseTask)
            phaseTask.project = project

            for (taskIndex, title) in phaseTemplate.starterTasks.enumerated() {
                let task = TodoTask(
                    workspaceID: workspaceID,
                    title: title,
                    sortOrder: taskIndex,
                    createdByID: createdBy
                )
                context.insert(task)
                task.project = project
                task.parentTask = phaseTask
            }
        }

        try context.save()
        return project
    }

    /// Instantiates a template task (D13): deep-copies the subtree as live
    /// tasks under the given destination. Works for single tasks and whole
    /// template phases ("Sottotitoli" and friends).
    @discardableResult
    static func instantiate(
        _ templateTask: TodoTask,
        under parent: TodoTask?,
        project: Project?,
        in context: ModelContext
    ) throws -> TodoTask {
        let copy = deepCopy(templateTask, in: context, asTemplate: false)
        copy.parentTask = parent
        assign(copy, to: project ?? parent?.project)
        try context.save()
        return copy
    }

    /// Duplicates a task (or whole phase subtree) next to the original (D46).
    @discardableResult
    static func duplicate(_ task: TodoTask, in context: ModelContext) throws -> TodoTask {
        let copy = deepCopy(task, in: context, asTemplate: task.isTemplate)
        copy.title = "\(task.title) (copia)"
        copy.sortOrder = task.sortOrder + 1
        copy.parentTask = task.parentTask
        assign(copy, to: task.project)
        try context.save()
        return copy
    }

    /// Marks a live subtree as a reusable template (blueprint).
    @discardableResult
    static func makeTemplate(from task: TodoTask, in context: ModelContext) throws -> TodoTask {
        let copy = deepCopy(task, in: context, asTemplate: true)
        copy.parentTask = nil
        copy.project = task.project
        try context.save()
        return copy
    }

    // MARK: Internals

    private static func deepCopy(
        _ source: TodoTask, in context: ModelContext, asTemplate: Bool
    ) -> TodoTask {
        let copy = TodoTask(
            workspaceID: source.workspaceID,
            title: source.title,
            notes: source.notes,
            kind: source.kind,
            priority: source.priority,
            allDay: source.allDay,
            timeZoneID: source.timeZoneID,
            locationName: source.locationName,
            videoCallURLString: source.videoCallURLString,
            attendees: source.attendees,
            alertOffsetsMinutes: source.alertOffsetsMinutes,
            isTemplate: asTemplate,
            sortOrder: source.sortOrder,
            createdByID: source.createdByID
        )
        copy.recurrenceFrequencyRaw = source.recurrenceFrequencyRaw
        copy.recurrenceInterval = source.recurrenceInterval
        copy.recurrenceModeRaw = source.recurrenceModeRaw
        context.insert(copy)
        for child in source.liveSubtasks {
            let childCopy = deepCopy(child, in: context, asTemplate: asTemplate)
            childCopy.parentTask = copy
        }
        return copy
    }

    private static func assign(_ task: TodoTask, to project: Project?) {
        task.project = project
        for child in task.liveSubtasks {
            assign(child, to: project)
        }
    }
}
