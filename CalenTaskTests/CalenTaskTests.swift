import Foundation
import SwiftData
import Testing
@testable import CalenTask

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Workspace.self, Membership.self, UserProfile.self,
        Project.self, TodoTask.self, TaskDependency.self, Tag.self,
        CustomFieldDefinition.self, CustomFieldValue.self, SavedView.self, WorkflowStage.self, AutomationRule.self, Attachment.self,
        Contact.self, CrewAssignment.self, ProductionScene.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
struct DomainModelTests {

    @Test func seedCreatesPersonalAndCompanyWorkspaces() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let first = try SeedService.ensureSeed(in: context)
        let second = try SeedService.ensureSeed(in: context)

        // Si parte da zero (D49): SOLO lo spazio personale e l'utente locale.
        #expect(first.me.id == second.me.id)
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Membership>()) == 1)

        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        #expect(workspaces.contains { $0.isPersonal && $0.name == SeedService.personalName })

        // Gli altri spazi li crea l'utente, con membership owner.
        let company = try SeedService.createWorkspace(
            name: "Mécena", colorHex: "#12A594", in: context
        )
        #expect(!company.isPersonal)
        #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Membership>()) == 2)
    }

    /// #9 — il "me" di iPhone ("Io") e quello del Mac (nome completo) sono la
    /// stessa persona: dopo il merge iCloud ne resta uno, mai un doppione eliminato.
    @Test func seedProfilesFromDifferentDevicesMergeRegardlessOfName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let phone = UserProfile(name: "Io", email: "", isLocalSeed: true)
        phone.createdAt = Date.now.addingTimeInterval(-3600)
        let mac = UserProfile(name: "Mario Rossi", email: "", isLocalSeed: true)
        let teammate = UserProfile(name: "Io", email: "")   // aggiunto a mano: mai fuso
        context.insert(phone)
        context.insert(mac)
        context.insert(teammate)
        try context.save()
        UserDefaults.standard.set(mac.id.uuidString, forKey: SeedService.userDefaultsKey)

        let (_, me) = try SeedService.ensureSeed(in: context)

        #expect(me.id == phone.id)
        #expect(me.deletedAt == nil)
        #expect(me.name == "Mario Rossi")
        #expect(mac.deletedAt != nil)
        #expect(teammate.deletedAt == nil)
    }

    @Test func subtaskCascadeDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let parent = TodoTask(workspaceID: workspace.id, title: "Padre", createdByID: me.id)
        let child1 = TodoTask(workspaceID: workspace.id, title: "Figlia 1", createdByID: me.id)
        let child2 = TodoTask(workspaceID: workspace.id, title: "Figlia 2", createdByID: me.id)
        context.insert(parent)
        context.insert(child1)
        context.insert(child2)
        child1.parentTask = parent
        child2.parentTask = parent
        try context.save()

        #expect(parent.subtasks.count == 2)
        context.delete(parent)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 0)
    }

    @Test func statusAndPriorityRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let task = TodoTask(workspaceID: workspace.id, title: "Test", createdByID: me.id)
        context.insert(task)
        task.status = .blocked
        task.priority = .urgent
        try context.save()

        #expect(task.statusRaw == "blocked")
        #expect(task.priorityRaw == TaskPriority.urgent.rawValue)
        #expect(task.status == .blocked)
        #expect(task.priority == .urgent)

        for status in TaskStatus.allCases {
            task.status = status
            #expect(TaskStatus(rawValue: task.statusRaw) == status)
        }
    }

    @Test func inboxPredicateExcludesProjectDonePhaseTemplateAndDeleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let project = Project(workspaceID: workspace.id, name: "Film", createdByID: me.id)
        context.insert(project)

        let inboxTask = TodoTask(workspaceID: workspace.id, title: "In inbox", createdByID: me.id)
        let projectTask = TodoTask(workspaceID: workspace.id, title: "Nel progetto", createdByID: me.id)
        let doneTask = TodoTask(workspaceID: workspace.id, title: "Fatta", status: .done, createdByID: me.id)
        let deletedTask = TodoTask(workspaceID: workspace.id, title: "Cestinata", createdByID: me.id)
        let phaseTask = TodoTask(workspaceID: workspace.id, title: "Fase orfana", kind: .phase, createdByID: me.id)
        let templateTask = TodoTask(workspaceID: workspace.id, title: "Modello", isTemplate: true, createdByID: me.id)
        for task in [inboxTask, projectTask, doneTask, deletedTask, phaseTask, templateTask] {
            context.insert(task)
        }
        projectTask.project = project
        deletedTask.deletedAt = .now
        try context.save()

        let results = try context.fetch(FetchDescriptor(predicate: TodoTask.inboxPredicate))

        #expect(results.count == 1)
        #expect(results.first?.title == "In inbox")
    }

    @Test func phaseSoftDeleteCascadesToChildren() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let project = Project(workspaceID: workspace.id, name: "Corto", createdByID: me.id)
        context.insert(project)
        let phase = TodoTask(workspaceID: workspace.id, title: "Riprese", kind: .phase, createdByID: me.id)
        context.insert(phase)
        phase.project = project

        let task = TodoTask(workspaceID: workspace.id, title: "Ordine del giorno", createdByID: me.id)
        context.insert(task)
        task.project = project
        task.parentTask = phase
        try context.save()

        phase.softDeleteSubtree()
        try context.save()

        #expect(phase.deletedAt != nil)
        #expect(task.deletedAt != nil)
        #expect(project.phaseTasks.isEmpty)
    }

    @Test func phaseAncestorAndAggregatedProgress() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let phase = TodoTask(workspaceID: workspace.id, title: "Post", kind: .phase, createdByID: me.id)
        let parent = TodoTask(workspaceID: workspace.id, title: "Montaggio", createdByID: me.id)
        let leaf1 = TodoTask(workspaceID: workspace.id, title: "Rough cut", createdByID: me.id)
        let leaf2 = TodoTask(workspaceID: workspace.id, title: "Fine cut", createdByID: me.id)
        for task in [phase, parent, leaf1, leaf2] { context.insert(task) }
        parent.parentTask = phase
        leaf1.parentTask = parent
        leaf2.parentTask = parent
        try context.save()

        #expect(leaf1.phaseAncestor?.id == phase.id)
        #expect(phase.aggregatedProgress == 0)

        leaf1.status = .done
        #expect(phase.aggregatedProgress == 0.5)
    }

    @Test func recurrenceFixedSpawnsNextOccurrenceOnCompletion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let calendar = Calendar.current
        let due = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9))!
        let task = TodoTask(workspaceID: workspace.id, title: "Affitto", dueAt: due, createdByID: me.id)
        context.insert(task)
        task.recurrenceFrequency = .monthly
        task.recurrenceMode = .fixed
        try context.save()

        task.toggleDone()
        try context.save()

        #expect(task.isDone)
        let all = try context.fetch(FetchDescriptor<TodoTask>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(all.count == 2)
        let next = try #require(all.first { $0.id != task.id })
        #expect(!next.isDone)
        #expect(next.hasRecurrence)
        let expected = calendar.date(byAdding: .month, value: 1, to: due)
        #expect(next.dueAt == expected)
    }

    @Test func recurrenceStopsAfterEndDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let due = Date.now
        let task = TodoTask(workspaceID: workspace.id, title: "Breve serie", dueAt: due, createdByID: me.id)
        context.insert(task)
        task.recurrenceFrequency = .daily
        task.recurrenceEndAt = due  // next occurrence falls after the end
        try context.save()

        task.toggleDone()
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
    }

    @Test func customFieldValueRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let field = CustomFieldDefinition(
            workspaceID: workspace.id, name: "Budget", type: .number
        )
        let task = TodoTask(workspaceID: workspace.id, title: "Scena 4", createdByID: me.id)
        context.insert(field)
        context.insert(task)

        let value = CustomFieldValue(
            workspaceID: workspace.id, fieldID: field.id, taskID: task.id
        )
        value.numberValue = 1500.5
        context.insert(value)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<CustomFieldValue>()).first)
        #expect(fetched.numberValue == 1500.5)
        #expect(fetched.fieldID == field.id)
        #expect(fetched.taskID == task.id)
    }

    @Test func automationRuleRunsOnStageEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        let eleonora = UserProfile(name: "Eleonora", email: "")
        context.insert(eleonora)

        let project = Project(workspaceID: workspace.id, name: "Concerto", createdByID: me.id)
        context.insert(project)
        let approved = WorkflowStage(
            workspaceID: workspace.id, projectID: project.id, name: "Approvato", order: 0
        )
        context.insert(approved)

        // L'esempio canonico (D31): Approvato → crea export, assegna, +2g.
        let rule = AutomationRule(
            workspaceID: workspace.id, projectID: project.id,
            name: "Export dopo approvazione", triggerType: .enteredStage
        )
        rule.triggerStageID = approved.id
        rule.createTaskTitle = "Preparare export — {task}"
        rule.createTaskAssigneeID = me.id
        rule.createTaskDueOffsetDays = 2
        rule.assignToID = eleonora.id
        context.insert(rule)

        let task = TodoTask(workspaceID: workspace.id, title: "Montaggio v3", createdByID: me.id)
        context.insert(task)
        task.project = project
        try context.save()

        task.move(toStage: approved)
        try context.save()

        let created = try #require(
            try context.fetch(FetchDescriptor<TodoTask>()).first { $0.title.hasPrefix("Preparare export") }
        )
        #expect(created.title == "Preparare export — Montaggio v3")

        // #10 — fuori e di nuovo dentro lo stadio: nessun follow-up doppio.
        task.move(toStage: nil)
        task.move(toStage: approved)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.title.hasPrefix("Preparare export") }.count == 1)
        #expect(created.assigneeID == me.id)
        #expect(created.project?.id == project.id)
        let expectedDue = Calendar.current.date(byAdding: .day, value: 2, to: .now.startOfDay)
        #expect(created.dueAt == expectedDue)
        // La task scatenante è stata riassegnata a Eleonora.
        #expect(task.assigneeID == eleonora.id)

        // Disabilitata ⇒ nessuna nuova task.
        rule.isEnabled = false
        task.move(toStage: nil)
        task.move(toStage: approved)
        let count = try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.title.hasPrefix("Preparare export") }.count
        #expect(count == 1)
    }

    @Test func hashtagParsingAndAccentColor() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        #expect(HashtagParser.tagNames(in: "Tagliare #montaggio per #Doc-2026 e #montaggio")
                == ["montaggio", "doc-2026"])
        #expect(HashtagParser.tagNames(in: "niente etichette").isEmpty)

        let task = TodoTask(
            workspaceID: workspace.id,
            title: "Sottotitoli #montaggio",
            notes: "vedi #revisione",
            createdByID: me.id
        )
        context.insert(task)
        TagService.syncTags(for: task, in: context)
        try context.save()

        #expect(Set(task.tags.map(\.name)) == ["montaggio", "revisione"])
        let montaggio = try #require(task.tags.first { $0.name == "montaggio" })
        montaggio.colorHex = "#2563EB"
        // First label in the TITLE wins (D21).
        #expect(task.accentTagColorHex == "#2563EB")

        // Re-sync after editing text: removed tags drop off, entities are reused.
        task.title = "Sottotitoli"
        TagService.syncTags(for: task, in: context)
        #expect(task.tags.map(\.name) == ["revisione"])
        let tagCount = try context.fetchCount(
            FetchDescriptor<CalenTask.Tag>(
                predicate: #Predicate<CalenTask.Tag> { $0.deletedAt == nil }
            )
        )
        #expect(tagCount == 2)  // "montaggio" survives as a workspace tag
    }

    @Test func italianRelativeDateParsing() throws {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 10))!

        // Il bug segnalato: "domani" da solo deve funzionare (D28).
        let bare = try #require(NaturalDateParser.parse("domani devo #montare quello", now: now))
        #expect(!bare.hasTime)
        #expect(bare.cleanedText == "devo #montare quello")
        #expect(calendar.isDate(bare.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!))

        // Giorno + ora.
        let timed = try #require(NaturalDateParser.parse("Domani alle 15 montaggio", now: now))
        #expect(timed.hasTime)
        #expect(timed.cleanedText == "montaggio")
        let timedComps = calendar.dateComponents([.day, .hour, .minute], from: timed.date)
        #expect(timedComps.day == 11 && timedComps.hour == 15 && timedComps.minute == 0)

        // Giorno della settimana con minuti (10/06/2026 è mercoledì → venerdì 12).
        let friday = try #require(NaturalDateParser.parse("venerdì alle 9:30 call produzione", now: now))
        #expect(friday.hasTime)
        #expect(friday.cleanedText == "call produzione")
        let fridayComps = calendar.dateComponents([.day, .hour, .minute], from: friday.date)
        #expect(fridayComps.day == 12 && fridayComps.hour == 9 && fridayComps.minute == 30)

        // "tra N giorni" e solo orario.
        let inDays = try #require(NaturalDateParser.parse("consegna tra 3 giorni", now: now))
        #expect(!inDays.hasTime)
        #expect(calendar.dateComponents([.day], from: inDays.date).day == 13)

        let timeOnly = try #require(NaturalDateParser.parse("chiama Marco alle 18", now: now))
        #expect(timeOnly.hasTime)
        #expect(timeOnly.cleanedText == "chiama Marco")
        #expect(calendar.component(.hour, from: timeOnly.date) == 18)
        #expect(calendar.isDate(timeOnly.date, inSameDayAs: now))
    }

    @Test func naturalDateParsing() throws {
        // Explicit numeric date+time: becomes a calendar event.
        let timed = try #require(NaturalDateParser.parse("Riunione produzione 12/09/2026 15:30"))
        #expect(timed.hasTime)
        #expect(timed.cleanedText == "Riunione produzione")
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: timed.date)
        #expect(comps.day == 12 && comps.month == 9 && comps.year == 2026)
        #expect(comps.hour == 15 && comps.minute == 30)

        // Date only: deadline, noon default is NOT treated as a time.
        let dated = try #require(NaturalDateParser.parse("Consegna documenti 12/09/2026"))
        #expect(!dated.hasTime)
        #expect(dated.cleanedText == "Consegna documenti")

        // No date at all.
        #expect(NaturalDateParser.parse("Comprare gelatine") == nil)
    }

    @Test func savedViewFiltersRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, _) = try SeedService.ensureSeed(in: context)

        var filters = SavedViewFilters()
        filters.statuses = [.doing, .blocked]
        filters.priorities = [.urgent]
        filters.dueWithinDays = 7

        let view = SavedView(
            workspaceID: workspace.id, name: "Urgenti settimana", viewType: .kanban, filters: filters
        )
        context.insert(view)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<SavedView>()).first)
        #expect(fetched.viewType == .kanban)
        #expect(fetched.filters == filters)
    }

    // MARK: v6 S3 — produzione video

    @Test func crewConflictDetectedAcrossProductions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let dop = Contact(workspaceID: workspace.id, name: "Luca", role: "DOP")
        context.insert(dop)

        let calendar = Calendar.current
        let day = calendar.date(bySettingHour: 8, minute: 0, second: 0,
                                of: .now.addingTimeInterval(86400))!

        // Due giorni di ripresa di produzioni diverse, stessa data.
        let dayA = TodoTask(workspaceID: workspace.id, title: "Giorno 1 — Concerto",
                            kind: .shootDay, startAt: day, createdByID: me.id)
        let dayB = TodoTask(workspaceID: workspace.id, title: "Giorno 1 — Documentario",
                            kind: .shootDay, startAt: day.addingTimeInterval(3600),
                            createdByID: me.id)
        context.insert(dayA)
        context.insert(dayB)
        context.insert(CrewAssignment(workspaceID: workspace.id,
                                      contactID: dop.id, taskID: dayA.id))
        context.insert(CrewAssignment(workspaceID: workspace.id,
                                      contactID: dop.id, taskID: dayB.id))
        try context.save()

        let conflicts = ConflictService.conflicts(
            contactID: dop.id, day: day, excludingTaskID: dayA.id, in: context
        )
        #expect(conflicts.map(\.id) == [dayB.id])
        #expect(ConflictService.conflictedContactIDs(for: dayA, in: context) == [dop.id])

        // Sciolto il conflitto (soft delete della convocazione B) → pulito.
        let assignments = try context.fetch(FetchDescriptor<CrewAssignment>())
        assignments.first { $0.taskID == dayB.id }?.deletedAt = .now
        try context.save()
        #expect(ConflictService.conflictedContactIDs(for: dayA, in: context).isEmpty)
    }

    @Test func sceneAssignmentAndPagesLabel() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let project = Project(workspaceID: workspace.id, name: "Corto", createdByID: me.id)
        context.insert(project)
        let day = TodoTask(workspaceID: workspace.id, title: "Giorno 1",
                           kind: .shootDay, startAt: .now, createdByID: me.id)
        context.insert(day)
        day.project = project

        let scene = ProductionScene(
            workspaceID: workspace.id, projectID: project.id,
            number: "12A", slug: "Inseguimento sul molo",
            intExt: .ext, dayNight: .night, pageEighths: 10
        )
        context.insert(scene)
        try context.save()

        #expect(scene.pagesLabel == "1 2/8")
        #expect(scene.shootDayID == nil)

        scene.shootDayID = day.id
        try context.save()
        let fetched = try #require(
            try context.fetch(FetchDescriptor<ProductionScene>()).first
        )
        #expect(fetched.shootDayID == day.id)
        #expect(fetched.intExt == .ext)
        #expect(fetched.dayNight == .night)
        // Il giorno di ripresa non finisce nell'inbox (ha progetto + kind dedicato).
        #expect(day.kind == .shootDay)
    }

    // MARK: v6 S4 — quick add esteso e smart list

    @Test func captureParserExtractsPriorityAndProject() throws {
        let parsed = CaptureParser.parse("montare il trailer !alta /Concerto #editing")
        #expect(parsed.priority == .high)
        #expect(parsed.projectQuery == "Concerto")
        #expect(parsed.title == "montare il trailer #editing")

        let urgent = CaptureParser.parse("chiamare il fonico !urgente")
        #expect(urgent.priority == .urgent)
        #expect(urgent.title == "chiamare il fonico")

        // Token attivo per l'autocomplete live.
        let tagToken = try #require(CaptureParser.activeToken(in: "comprare gel #se"))
        #expect(tagToken.prefix == "#" && tagToken.query == "se")
        let projToken = try #require(CaptureParser.activeToken(in: "ciak /Doc"))
        #expect(projToken.prefix == "/" && projToken.query == "Doc")
        #expect(CaptureParser.activeToken(in: "niente token ") == nil)
    }

    @Test func smartListFiltersMatchTasks() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let urgentTask = TodoTask(workspaceID: workspace.id, title: "Urgente",
                                  priority: .urgent,
                                  dueAt: .now.startOfDay, createdByID: me.id)
        let lowFar = TodoTask(workspaceID: workspace.id, title: "Con calma",
                              priority: .low,
                              dueAt: Calendar.current.date(byAdding: .day, value: 30, to: .now),
                              createdByID: me.id)
        let done = TodoTask(workspaceID: workspace.id, title: "Fatta",
                            priority: .urgent, createdByID: me.id)
        done.status = .done
        context.insert(urgentTask)
        context.insert(lowFar)
        context.insert(done)
        try context.save()

        var filters = SavedViewFilters()
        filters.priorities = [.urgent]
        filters.dueWithinDays = 7
        #expect(filters.matches(urgentTask))
        #expect(!filters.matches(lowFar))     // priorità e scadenza fuori range
        #expect(!filters.matches(done))       // completata, includeDone = false

        filters.includeDone = true
        filters.dueWithinDays = nil
        #expect(filters.matches(done))
    }

    // MARK: v6 S7 — regressione ricorrenze + notifiche (il killer dei competitor)

    @Test func recurrenceAfterCompletionAdvancesFromTodayKeepingTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        let calendar = Calendar.current

        // Scadenza VECCHIA di 10 giorni alle 14:30, ripetizione settimanale
        // "dopo il completamento": la prossima è oggi+7 alle 14:30 — non
        // nel passato (l'errore classico delle app concorrenti).
        let oldDue = calendar.date(
            bySettingHour: 14, minute: 30, second: 0,
            of: calendar.date(byAdding: .day, value: -10, to: .now)!
        )!
        let task = TodoTask(workspaceID: workspace.id, title: "Backup settimanale",
                            dueAt: oldDue, createdByID: me.id)
        task.recurrenceFrequency = .weekly
        task.recurrenceInterval = 1
        task.recurrenceMode = .afterCompletion
        context.insert(task)
        try context.save()

        task.toggleDone()
        try context.save()

        let spawned = try #require(
            try context.fetch(FetchDescriptor<TodoTask>())
                .first { $0.id != task.id && $0.title == "Backup settimanale" }
        )
        let due = try #require(spawned.dueAt)
        let expectedDay = calendar.date(byAdding: .day, value: 7, to: .now)!
        #expect(calendar.isDate(due, inSameDayAs: expectedDay))
        let time = calendar.dateComponents([.hour, .minute], from: due)
        #expect(time.hour == 14 && time.minute == 30)
        #expect(!spawned.isDone)
    }

    @Test func recurrenceDoesNotSpawnOnReopen() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let task = TodoTask(workspaceID: workspace.id, title: "Report mensile",
                            dueAt: .now.startOfDay, createdByID: me.id)
        task.recurrenceFrequency = .monthly
        task.recurrenceInterval = 1
        context.insert(task)
        try context.save()

        task.toggleDone()     // completa → genera la prossima
        task.toggleDone()     // riapre → NON deve generarne un'altra
        task.toggleDone()     // ricompleta → la prossima esiste già: nessun doppione (#8)
        try context.save()

        let clones = try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.title == "Report mensile" }
        #expect(clones.count == 2)   // originale + UNA sola occorrenza successiva

        // Completare dal menu Stato (setStatus) genera la successiva come il checkbox.
        let next = try #require(clones.first { $0.id != task.id })
        next.setStatus(.done)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.title == "Report mensile" }.count == 3)
    }

    @Test func dueFireDateMovesMidnightToNineKeepsExplicitTimes() {
        let calendar = Calendar.current
        let midnight = Date.now.startOfDay
        let nineAM = NotificationService.dueFireDate(for: midnight)
        #expect(calendar.component(.hour, from: nineAM) == 9)
        #expect(calendar.isDate(nineAM, inSameDayAs: midnight))

        let explicit = calendar.date(bySettingHour: 17, minute: 45, second: 0,
                                     of: .now)!
        #expect(NotificationService.dueFireDate(for: explicit) == explicit)
    }

    /// #4 — gli avvisi dell'evento generano notifiche; quelli passati no;
    /// completate e template non notificano.
    @Test func eventAlertsAreScheduledRelativeToStart() {
        let now = Date.now
        let start = now.addingTimeInterval(2 * 3600)
        let task = TodoTask(workspaceID: UUID(), title: "Riunione", kind: .event,
                            startAt: start, alertOffsetsMinutes: [15, 60, 180, 15],
                            createdByID: UUID())
        let schedule = NotificationService.plannedSchedule(for: task, now: now)
        let alertIDs = Set(schedule.map { $0.id }.filter { $0.contains("-alert-") })
        #expect(alertIDs == [
            NotificationService.alertID(task.id, minutesBefore: 15),
            NotificationService.alertID(task.id, minutesBefore: 60),
        ])   // -180 min è già passato, il doppione 15 conta una volta
        let fifteen = schedule.first { $0.id == NotificationService.alertID(task.id, minutesBefore: 15) }
        #expect(fifteen?.fireDate == start.addingTimeInterval(-15 * 60))
        #expect(schedule.allSatisfy { $0.id.hasPrefix(NotificationService.taskPrefix(task.id)) })

        task.statusRaw = TaskStatus.done.rawValue
        #expect(NotificationService.plannedSchedule(for: task, now: now).isEmpty)
        task.statusRaw = TaskStatus.todo.rawValue
        task.isTemplate = true
        #expect(NotificationService.plannedSchedule(for: task, now: now).isEmpty)
    }

    /// #1 — i collegamenti evento↔task sono per dispositivo, persistono e
    /// una task ha al massimo un evento locale.
    @Test func eventLinkRegistryPersistsPerDeviceLinks() throws {
        let suite = "EventLinkRegistryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let task = UUID()
        var registry = EventLinkRegistry(defaults: defaults)
        #expect(!registry.isLinkedHere(task))
        registry.link(event: "EV-1", to: task)
        registry.link(event: "EV-2", to: task)   // sostituisce EV-1

        let reloaded = EventLinkRegistry(defaults: defaults)
        #expect(reloaded.taskID(forEvent: "EV-2") == task)
        #expect(reloaded.taskID(forEvent: "EV-1") == nil)
        #expect(reloaded.eventIdentifier(forTask: task) == "EV-2")
        #expect(reloaded.isLinkedHere(task))

        registry.unlink(event: "EV-2")
        #expect(EventLinkRegistry(defaults: defaults).links.isEmpty)
    }

    /// #2 — ogni occorrenza di una serie ha la sua chiave (serie + data
    /// originale), distinta dagli id semplici: due settimane = due task.
    @Test func recurringEventOccurrencesHaveDistinctKeys() throws {
        let suite = "EventLinkRegistryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let monday = Date(timeIntervalSince1970: 1_790_000_000)
        let first = EventLinkRegistry.occurrenceKey(series: "UID|riunione", occurrenceDate: monday)
        let second = EventLinkRegistry.occurrenceKey(
            series: "UID|riunione", occurrenceDate: monday.addingTimeInterval(7 * 86_400)
        )
        #expect(first != second)
        let parsed = try #require(EventLinkRegistry.occurrence(fromKey: first))
        #expect(parsed.series == "UID|riunione")
        #expect(parsed.date == monday)
        #expect(EventLinkRegistry.occurrence(fromKey: "EV-1")?.series == nil)
        #expect(EventLinkRegistry.occurrence(fromKey: "occ||123")?.series == nil)

        let taskA = UUID(), taskB = UUID()
        var registry = EventLinkRegistry(defaults: defaults)
        registry.link(event: first, to: taskA)
        registry.link(event: second, to: taskB)
        let reloaded = EventLinkRegistry(defaults: defaults)
        #expect(reloaded.taskID(forEvent: first) == taskA)
        #expect(reloaded.taskID(forEvent: second) == taskB)
    }

    /// #2 — una serie resta "dell'app" solo se la task è nata prima
    /// dell'evento; le note si uniscono invece di essere sovrascritte.
    @Test func calendarSeriesOwnershipAndNotesMerge() {
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(CalendarSyncService.isAppOwnedSeries(
            taskSource: .capture, taskCreatedAt: created, eventCreatedAt: created.addingTimeInterval(5)
        ))
        // Import del codice vecchio: task nata dopo l'evento di sistema.
        #expect(!CalendarSyncService.isAppOwnedSeries(
            taskSource: .capture, taskCreatedAt: created, eventCreatedAt: created.addingTimeInterval(-86_400)
        ))
        #expect(!CalendarSyncService.isAppOwnedSeries(
            taskSource: .imported, taskCreatedAt: created, eventCreatedAt: nil
        ))
        #expect(CalendarSyncService.isAppOwnedSeries(
            taskSource: .capture, taskCreatedAt: created, eventCreatedAt: nil
        ))

        #expect(CalendarSyncService.mergedNotes(local: "Portare il contratto", remote: nil) == "Portare il contratto")
        #expect(CalendarSyncService.mergedNotes(local: "", remote: "Sala B") == "Sala B")
        #expect(CalendarSyncService.mergedNotes(
            local: "Portare il contratto\n\nSala B", remote: "Sala B"
        ) == "Portare il contratto\n\nSala B")
        #expect(CalendarSyncService.mergedNotes(local: "Sala B", remote: "Sala B, 2° piano") == "Sala B, 2° piano")
        #expect(CalendarSyncService.mergedNotes(
            local: "Portare il contratto", remote: "Sala B"
        ) == "Portare il contratto\n\nSala B")
    }

    /// #5 — il calendario carica dallo store solo la finestra visibile e lo
    /// spazio scelto: eventi su più giorni e fasi che la attraversano ci
    /// sono, il resto no.
    @Test func calendarWindowPredicatesFilterInStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        let calendar = Calendar.app
        func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        @discardableResult
        func add(_ title: String, kind: TaskKind = .task, status: TaskStatus = .todo,
                 start: Date? = nil, end: Date? = nil, due: Date? = nil,
                 workspaceID: UUID? = nil) -> TodoTask {
            let task = TodoTask(workspaceID: workspaceID ?? workspace.id, title: title, kind: kind,
                                status: status, startAt: start, endAt: end, dueAt: due,
                                createdByID: me.id)
            context.insert(task)
            return task
        }

        add("Riunione", kind: .event, start: day(2026, 10, 10), end: day(2026, 10, 10, 11))
        add("Trasferta", kind: .event, start: day(2026, 8, 1), end: day(2026, 9, 1))
        add("Fase", kind: .phase, start: day(2026, 6, 1), due: day(2026, 12, 31))
        add("Scadenza", due: day(2026, 11, 5))
        add("Da pianificare")
        add("Fatta senza date", status: .done)
        add("Lontana", kind: .event, start: day(2027, 3, 1), end: day(2027, 3, 1, 11))
        add("Scaduta a gennaio", due: day(2026, 1, 10))
        add("Cancellata", kind: .event, start: day(2026, 10, 10)).deletedAt = .now
        let other = UUID()
        add("Altro spazio", kind: .event, start: day(2026, 10, 12), workspaceID: other)

        let window = CalendarScreen.loadWindow(for: .month, around: day(2026, 10, 15), calendar: calendar)
        #expect(window.contains(day(2026, 10, 1)) && window.contains(day(2026, 10, 31)))
        #expect(!window.contains(day(2027, 3, 1)))

        func titles(_ workspaceID: UUID?) throws -> Set<String> {
            let started = try context.fetch(FetchDescriptor(predicate: TodoTask.calendarStartPredicate(
                from: window.start, to: window.end, workspaceID: workspaceID
            )))
            let due = try context.fetch(FetchDescriptor(predicate: TodoTask.calendarDuePredicate(
                from: window.start, to: window.end, workspaceID: workspaceID
            )))
            let unscheduled = try context.fetch(FetchDescriptor(
                predicate: TodoTask.unscheduledPredicate(workspaceID: workspaceID)
            ))
            return Set(TodoTask.mergingUnique(started, due, unscheduled).map(\.title))
        }
        #expect(try titles(workspace.id) == ["Riunione", "Trasferta", "Fase", "Scadenza", "Da pianificare"])
        #expect(try titles(nil).contains("Altro spazio"))

        #expect(try context.fetchCount(FetchDescriptor(predicate: TodoTask.openPredicate(workspaceID: other))) == 1)
        #expect(try context.fetchCount(FetchDescriptor(predicate: TodoTask.inboxPredicate(workspaceID: other))) == 1)
        #expect(WorkspaceScope.filter([workspace], raw: other.uuidString, id: \.id).isEmpty)
        #expect(WorkspaceScope.filter([workspace], raw: workspace.id.uuidString, id: \.id).count == 1)
    }

    @Test func freeSlotsSkipBusyIntervals() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        let calendar = Calendar.current

        // Domani: 9-12 occupato, 14-16 occupato → con "adesso" fissato a
        // domani alle 8:00 i primi slot da 1h sono 8:00, 12:00, 16:00.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now.startOfDay)!
        let busy1 = TodoTask(workspaceID: workspace.id, title: "Riunione", kind: .event,
                             startAt: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow),
                             endAt: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow),
                             createdByID: me.id)
        let busy2 = TodoTask(workspaceID: workspace.id, title: "Sopralluogo", kind: .event,
                             startAt: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow),
                             endAt: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: tomorrow),
                             createdByID: me.id)
        context.insert(busy1)
        context.insert(busy2)

        let probe = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        let slots = CalendarScreen.freeSlots(
            duration: 60, in: [busy1, busy2], calendar: calendar, now: probe
        )
        #expect(slots.count == 3)
        #expect(calendar.component(.hour, from: slots[0]) == 8)
        #expect(calendar.component(.hour, from: slots[1]) == 12)
        #expect(calendar.component(.hour, from: slots[2]) == 16)
    }

    @Test func contactsImportDedupesByIdentifierAndEmail() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (workspace, _) = try SeedService.ensureSeed(in: context)

        // Già in rubrica: una collegata (identifier) e una solo nostra (email).
        let linked = Contact(workspaceID: workspace.id, name: "Anna Verdi",
                             phone: "+39 111", email: "anna@example.com")
        linked.contactIdentifier = "CN-ANNA"
        let unlinked = Contact(workspaceID: workspace.id, name: "Bruno Bianchi",
                               email: "Bruno@Example.com")
        context.insert(linked)
        context.insert(unlinked)
        try context.save()

        let picks: [ContactsImportService.DeviceContact] = [
            // Stessa identity → aggiorna telefono, non duplica.
            .init(id: "CN-ANNA", fullName: "Anna Verdi", organization: "",
                  phone: "+39 222", email: "anna@example.com"),
            // Stessa email (case-insensitive) → collega l'identifier.
            .init(id: "CN-BRUNO", fullName: "Bruno Bianchi", organization: "",
                  phone: "+39 333", email: "bruno@example.com"),
            // Nuovo → si crea.
            .init(id: "CN-CARLA", fullName: "Carla Neri", organization: "Studio Neri",
                  phone: "", email: "carla@example.com"),
        ]
        let created = try ContactsImportService.importContacts(
            picks, workspaceID: workspace.id, into: context
        )

        #expect(created == 1)
        let all = try context.fetch(FetchDescriptor<Contact>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        #expect(all.count == 3)
        #expect(linked.phone == "+39 222")
        #expect(unlinked.contactIdentifier == "CN-BRUNO")
        #expect(unlinked.phone == "+39 333")
        let carla = try #require(all.first { $0.name == "Carla Neri" })
        #expect(carla.contactIdentifier == "CN-CARLA")
        #expect(carla.notes == "Studio Neri")
    }
}
