import Foundation
import SwiftData
import Testing
@testable import CalenTask

/// #19 — `AutomationEngine`: il follow-up non si duplica finché il primo è aperto.
@MainActor
struct AutomationEngineTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Membership.self, UserProfile.self,
            Project.self, TodoTask.self, TaskDependency.self, Tag.self,
            CustomFieldDefinition.self, CustomFieldValue.self, SavedView.self,
            WorkflowStage.self, AutomationRule.self, Attachment.self,
            Contact.self, CrewAssignment.self, ProductionScene.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func followUps(in context: ModelContext) throws -> [TodoTask] {
        try context.fetch(FetchDescriptor<TodoTask>()).filter { $0.source == .automation }
    }

    @Test func doneReopenDoneCreatesSingleFollowUp() throws {
        let context = try makeContext()
        let ws = UUID(), author = UUID()
        let project = Project(workspaceID: ws, name: "P", createdByID: author)
        context.insert(project)
        let rule = AutomationRule(
            workspaceID: ws, projectID: project.id, name: "Export",
            triggerType: .statusChanged
        )
        rule.triggerStatus = .done
        rule.createTaskTitle = "Export {task}"
        context.insert(rule)
        let task = TodoTask(workspaceID: ws, title: "Montaggio", createdByID: author)
        context.insert(task)
        task.project = project
        try context.save()

        task.setStatus(.done)
        task.setStatus(.todo)
        task.setStatus(.done)

        let created = try followUps(in: context)
        #expect(created.count == 1)
        #expect(created.first?.title == "Export Montaggio")
    }

    @Test func disabledRuleCreatesNothing() throws {
        let context = try makeContext()
        let ws = UUID(), author = UUID()
        let project = Project(workspaceID: ws, name: "P", createdByID: author)
        context.insert(project)
        let rule = AutomationRule(
            workspaceID: ws, projectID: project.id, name: "Off",
            triggerType: .statusChanged
        )
        rule.triggerStatus = .done
        rule.createTaskTitle = "Extra"
        rule.isEnabled = false
        context.insert(rule)
        let task = TodoTask(workspaceID: ws, title: "T", createdByID: author)
        context.insert(task)
        task.project = project
        try context.save()

        task.setStatus(.done)
        #expect(try followUps(in: context).isEmpty)
    }
}
