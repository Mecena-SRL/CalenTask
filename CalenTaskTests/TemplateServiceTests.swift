import Foundation
import SwiftData
import Testing
@testable import CalenTask

@MainActor
struct TemplateServiceTests {

    // The container must be returned too: dropping it deallocates the store
    // out from under mainContext and crashes the test process.
    private func makeContext() throws -> (ModelContainer, ModelContext, Workspace, UserProfile) {
        let schema = Schema([
            Workspace.self, Membership.self, UserProfile.self,
            Project.self, TodoTask.self, TaskDependency.self, Tag.self,
            CustomFieldDefinition.self, CustomFieldValue.self, SavedView.self, WorkflowStage.self, AutomationRule.self, Attachment.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        return (container, context, workspace, me)
    }

    @Test func featureTemplateCreatesPhaseTasksAndChildren() throws {
        let (container, context, workspace, me) = try makeContext()
        defer { _ = container }

        let project = try TemplateService.apply(
            TemplateCatalog.feature,
            projectName: "Il mio film",
            workspaceID: workspace.id,
            createdBy: me.id,
            in: context
        )

        #expect(project.name == "Il mio film")
        #expect(project.phaseTasks.count == 5)
        #expect(project.phaseTasks.allSatisfy { $0.kind == .phase })
        #expect(project.phaseTasks.map(\.title) == [
            "Sviluppo", "Pre-produzione", "Riprese", "Post-produzione", "Distribuzione e promozione",
        ])

        // Every task (phases + lavorazioni) belongs to the project.
        let starterCount = TemplateCatalog.feature.phases
            .map(\.starterTasks.count)
            .reduce(0, +)
        #expect(project.tasks.count == starterCount + 5)

        // Starter tasks keep template order within each phase.
        let preProduzione = try #require(project.phaseTasks.first { $0.title == "Pre-produzione" })
        let sortedTitles = preProduzione.liveSubtasks.map(\.title)
        #expect(sortedTitles.first == "Spoglio della sceneggiatura")
        #expect(sortedTitles.count == 13)
        #expect(preProduzione.liveSubtasks.allSatisfy { $0.phaseAncestor?.id == preProduzione.id })
    }

    @Test func emptyTemplateCreatesBareProject() throws {
        let (container, context, workspace, me) = try makeContext()
        defer { _ = container }

        let project = try TemplateService.apply(
            TemplateCatalog.empty,
            projectName: "Da zero",
            workspaceID: workspace.id,
            createdBy: me.id,
            in: context
        )

        #expect(project.phaseTasks.isEmpty)
        #expect(project.tasks.isEmpty)
    }

    @Test func makeTemplateAndInstantiateDeepCopiesSubtree() throws {
        let (container, context, workspace, me) = try makeContext()
        defer { _ = container }

        let project = Project(workspaceID: workspace.id, name: "Doc", createdByID: me.id)
        context.insert(project)
        let phase = TodoTask(workspaceID: workspace.id, title: "Sottotitoli", kind: .phase, createdByID: me.id)
        context.insert(phase)
        phase.project = project
        for (index, title) in ["Trascrizione", "Traduzione", "Sync"].enumerated() {
            let child = TodoTask(workspaceID: workspace.id, title: title, sortOrder: index, createdByID: me.id)
            context.insert(child)
            child.parentTask = phase
            child.project = project
        }
        try context.save()

        // Freeze the subtree as a blueprint…
        let blueprint = try TemplateService.makeTemplate(from: phase, in: context)
        #expect(blueprint.isTemplate)
        #expect(blueprint.liveSubtasks.count == 3)
        #expect(blueprint.liveSubtasks.allSatisfy { $0.isTemplate })

        // …then stamp out a live copy.
        let copy = try TemplateService.instantiate(blueprint, under: nil, project: project, in: context)
        #expect(!copy.isTemplate)
        #expect(copy.kind == .phase)
        #expect(copy.liveSubtasks.map(\.title) == ["Trascrizione", "Traduzione", "Sync"])
        #expect(copy.liveSubtasks.allSatisfy { !$0.isTemplate && $0.project?.id == project.id })

        // Blueprints never pollute the operational lists.
        #expect(!project.phaseTasks.contains { $0.id == blueprint.id })
        #expect(project.phaseTasks.contains { $0.id == copy.id })
    }

    @Test func catalogIsWellFormed() {
        #expect(TemplateCatalog.all.count == 10)
        let ids = Set(TemplateCatalog.all.map(\.id))
        #expect(ids.count == TemplateCatalog.all.count)
        #expect(TemplateCatalog.templates(in: .cinema).count == 6)
        #expect(TemplateCatalog.templates(in: .business).count == 3)
        for template in TemplateCatalog.all {
            for phase in template.phases {
                #expect(!phase.name.isEmpty)
                #expect(phase.starterTasks.allSatisfy { !$0.isEmpty })
            }
            #expect(template.stages.allSatisfy { !$0.isEmpty })
        }
    }

    @Test func mecenaTemplatesCreatePipeline() throws {
        let (container, context, workspace, me) = try makeContext()
        defer { _ = container }

        let project = try TemplateService.apply(
            TemplateCatalog.concert,
            projectName: "Concerto Teatro Regio",
            workspaceID: workspace.id,
            createdBy: me.id,
            in: context
        )

        let stages = try context.fetch(FetchDescriptor<WorkflowStage>(
            sortBy: [SortDescriptor(\.order)]
        )).filter { $0.projectID == project.id }

        #expect(stages.map(\.name) == [
            "Preventivo", "Conferma", "Scheda tecnica", "Troupe", "Riprese",
            "Ingest", "Sync", "Montaggio integrale", "Export",
            "Estratti social", "Fattura", "Archivio",
        ])
        #expect(stages.last?.isTerminal == true)
        #expect(stages.dropLast().allSatisfy { !$0.isTerminal })
        #expect(Set(stages.map(\.colorHex)).count > 1)

        // Moving a task along the pipeline.
        let task = try #require(project.tasks.first { !$0.isPhase })
        task.move(toStage: stages[1])
        #expect(task.stageID == stages[1].id)
        task.move(toStage: nil)
        #expect(task.stageID == nil)
    }
}
