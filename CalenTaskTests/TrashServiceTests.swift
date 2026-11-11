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

    @Test func restoreBringsBackSubtree() throws {
        let context = try makeContext()
        let author = UUID(), ws = UUID()
        let parent = TodoTask(workspaceID: ws, title: "Padre", createdByID: author)
        let child = TodoTask(workspaceID: ws, title: "Figlio", createdByID: author)
        context.insert(parent); context.insert(child)
        child.parentTask = parent
        parent.softDeleteSubtree()
        #expect(TrashService.trashedRoots(in: context).map(\.title) == ["Padre"])

        TrashService.restore(parent)
        #expect(parent.deletedAt == nil && child.deletedAt == nil)
        #expect(TrashService.trashedRoots(in: context).isEmpty)
    }

    @Test func emptyTrashRemovesOnlyDeleted() throws {
        let context = try makeContext()
        let author = UUID(), ws = UUID()
        let gone = TodoTask(workspaceID: ws, title: "Via", createdByID: author)
        let live = TodoTask(workspaceID: ws, title: "Viva", createdByID: author)
        context.insert(gone); context.insert(live)
        gone.deletedAt = .now
        #expect(TrashService.emptyTrash(in: context) == 1)
        #expect(try context.fetch(FetchDescriptor<TodoTask>()).map(\.title) == ["Viva"])
    }

    /// Toast "Eliminata · Annulla": ripristino per ID, solo se è nel cestino.
    @Test func restoreByIDOnlyTouchesTrashedTask() throws {
        let context = try makeContext()
        let author = UUID(), ws = UUID()
        let task = TodoTask(workspaceID: ws, title: "Annullabile", createdByID: author)
        context.insert(task)
        try context.save()

        #expect(TrashService.restore(taskID: task.id, in: context) == false)
        task.softDelete()
        #expect(TrashService.restore(taskID: task.id, in: context))
        #expect(task.deletedAt == nil)
        #expect(TrashService.restore(taskID: UUID(), in: context) == false)
    }
}
