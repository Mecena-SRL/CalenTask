import Foundation
import SwiftData
import Testing
@testable import CalenTask

/// #19 — `SeedService.dedupeAfterCloudMerge` (via `ensureSeed`): fonde solo ciò
/// che il seed genera da sé, mai spazi o persone creati dall'utente.
@MainActor
struct SeedDedupeTests {

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

    /// Due spazi "Personale" (due dispositivi prima del merge) → ne resta uno
    /// e le attività del doppione vengono ripuntate; lo spazio utente non si tocca.
    @Test func duplicatePersonalWorkspacesAreMerged() throws {
        let context = try makeContext()
        let old = Workspace(name: "Personale", isPersonal: true,
                            createdAt: Date(timeIntervalSince1970: 1_000))
        let dup = Workspace(name: "Personale", isPersonal: true,
                            createdAt: Date(timeIntervalSince1970: 2_000))
        let custom = Workspace(name: "Personale", isPersonal: false)
        let author = UUID()
        let task = TodoTask(workspaceID: dup.id, title: "Dal doppione", createdByID: author)
        [old, dup, custom].forEach { context.insert($0) }
        context.insert(task)
        try context.save()

        _ = try SeedService.ensureSeed(in: context)

        #expect(old.deletedAt == nil)
        #expect(dup.deletedAt != nil)
        #expect(custom.deletedAt == nil)
        #expect(task.workspaceID == old.id)
    }

    /// Profili "me" auto-generati → uno solo, con il nome più parlante;
    /// un profilo aggiunto a mano resta intatto.
    @Test func seedProfilesMergeButManualOnesSurvive() throws {
        let context = try makeContext()
        let first = UserProfile(name: "Io", email: "", createdAt: Date(timeIntervalSince1970: 1_000),
                                isLocalSeed: true)
        let second = UserProfile(name: "Ivan Rossi", email: "", createdAt: Date(timeIntervalSince1970: 2_000),
                                 isLocalSeed: true)
        let manual = UserProfile(name: "Io", email: "a@b.it", createdAt: Date(timeIntervalSince1970: 3_000))
        let task = TodoTask(workspaceID: UUID(), title: "Mia", createdByID: second.id)
        [first, second, manual].forEach { context.insert($0) }
        context.insert(task)
        try context.save()

        _ = try SeedService.ensureSeed(in: context)

        #expect(first.deletedAt == nil)
        #expect(first.name == "Ivan Rossi")
        #expect(second.deletedAt != nil)
        #expect(manual.deletedAt == nil)
        #expect(task.createdByID == first.id)
    }
}
