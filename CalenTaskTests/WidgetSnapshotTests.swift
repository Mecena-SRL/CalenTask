import Foundation
import SwiftData
import Testing
@testable import CalenTask

/// #19 — snapshot del widget: cosa finisce in "oggi", arretrati e Inbox.
@MainActor
struct WidgetSnapshotTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Membership.self, UserProfile.self,
            Project.self, TodoTask.self, TaskDependency.self, Tag.self,
            CustomFieldDefinition.self, CustomFieldValue.self, SavedView.self, WorkflowStage.self, AutomationRule.self, Attachment.self,
            Contact.self, CrewAssignment.self, ProductionScene.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config]).mainContext
    }

    @Test func snapshotCountsTodayOverdueAndInbox() throws {
        let context = try makeContext()
        let ws = UUID(), me = UUID()
        let now = try #require(Calendar.app.date(
            bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        let today = now.startOfDay

        let todayTask = TodoTask(workspaceID: ws, title: "Oggi", dueAt: today.addingTimeInterval(14 * 3600), createdByID: me)
        let overdue = TodoTask(workspaceID: ws, title: "Arretrato", dueAt: today.addingTimeInterval(-86_400), createdByID: me)
        let deleted = TodoTask(workspaceID: ws, title: "Eliminata", dueAt: today.addingTimeInterval(14 * 3600), createdByID: me)
        deleted.deletedAt = now
        for task in [todayTask, overdue, deleted] { context.insert(task) }

        let snapshot = try WidgetBridge.makeSnapshot(in: context, now: now)
        #expect(snapshot.generatedAt == now)
        #expect(snapshot.items.map(\.title) == ["Oggi"])
        #expect(snapshot.overdueCount == 1)
        #expect(snapshot.inboxCount == 2)
    }
}
