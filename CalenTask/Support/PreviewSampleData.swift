import Foundation
import SwiftData

/// In-memory container with realistic sample data for #Preview.
@MainActor
enum PreviewSampleData {
    struct Bundle {
        let container: ModelContainer
        let workspace: Workspace
        let me: UserProfile
        let project: Project
        let tasks: [TodoTask]
    }

    static func make() -> Bundle {
        let schema = Schema([
            Workspace.self, Membership.self, UserProfile.self,
            Project.self, TodoTask.self, TaskDependency.self, Tag.self,
            CustomFieldDefinition.self, CustomFieldValue.self, SavedView.self, WorkflowStage.self, AutomationRule.self, Attachment.self,
            Contact.self, CrewAssignment.self, ProductionScene.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let (workspace, me) = try! SeedService.ensureSeed(in: context)

        let project = Project(
            workspaceID: workspace.id, name: "Cortometraggio Aurora",
            colorHex: "#0E7490", createdByID: me.id
        )
        context.insert(project)

        let phase = TodoTask(
            workspaceID: workspace.id, title: "Pre-produzione", kind: .phase,
            createdByID: me.id
        )
        context.insert(phase)
        phase.project = project

        let calendar = Calendar.current
        let today = Date.now
        let samples: [TodoTask] = [
            TodoTask(workspaceID: workspace.id, title: "Chiamare il direttore della fotografia",
                     priority: .high, dueAt: today, createdByID: me.id),
            TodoTask(workspaceID: workspace.id, title: "Sopralluogo location villa",
                     startAt: calendar.date(byAdding: .hour, value: 3, to: today),
                     remindAt: calendar.date(byAdding: .hour, value: 2, to: today),
                     createdByID: me.id),
            TodoTask(workspaceID: workspace.id, title: "Preventivo noleggio camera",
                     status: .doing, createdByID: me.id),
            TodoTask(workspaceID: workspace.id, title: "Contratto attrice protagonista",
                     status: .blocked, priority: .urgent,
                     dueAt: calendar.date(byAdding: .day, value: -2, to: today),
                     createdByID: me.id),
            TodoTask(workspaceID: workspace.id, title: "Ordinare gelatine per le luci",
                     status: .done, createdByID: me.id),
            TodoTask(workspaceID: workspace.id, title: "Idea: documentario sul porto",
                     createdByID: me.id),
        ]
        for (index, task) in samples.enumerated() {
            task.sortOrder = index
            context.insert(task)
        }
        // First four belong to the project; the last two stay in the Inbox.
        for task in samples.prefix(4) {
            task.project = project
            task.parentTask = phase
        }
        try! context.save()

        return Bundle(container: container, workspace: workspace, me: me, project: project, tasks: samples)
    }
}
