import Foundation
import SwiftData
import Testing
@testable import CalenTask

/// #22 — `TrashService.purgeExpired`: elimina solo ciò che è nel cestino da oltre 30 giorni.
@MainActor
struct TrashServiceTests {

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

    @Test func purgesOnlyExpiredDeletedTasks() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let author = UUID(), ws = UUID()
        let old = TodoTask(workspaceID: ws, title: "Vecchia", createdByID: author)
        old.deletedAt = now.addingTimeInterval(-31 * 86_400)
        let recent = TodoTask(workspaceID: ws, title: "Recente", createdByID: author)
        recent.deletedAt = now.addingTimeInterval(-5 * 86_400)
        let live = TodoTask(workspaceID: ws, title: "Viva", createdByID: author)
        [old, recent, live].forEach { context.insert($0) }
        try context.save()

        #expect(TrashService.purgeExpired(in: context, now: now) == 1)
        let titles = try context.fetch(FetchDescriptor<TodoTask>()).map(\.title).sorted()
        #expect(titles == ["Recente", "Viva"])
    }

    @Test func restoreSubtreeBringsBackChildrenToo() throws {
        let context = try makeContext()
        let author = UUID(), ws = UUID()
        let parent = TodoTask(workspaceID: ws, title: "Padre", createdByID: author)
        let child = TodoTask(workspaceID: ws, title: "Figlio", createdByID: author)
        context.insert(parent)
        context.insert(child)
        child.parentTask = parent
        parent.softDeleteSubtree()
        #expect(parent.deletedAt != nil && child.deletedAt != nil)

        parent.restoreSubtree()
        #expect(parent.deletedAt == nil && child.deletedAt == nil)
    }
}
