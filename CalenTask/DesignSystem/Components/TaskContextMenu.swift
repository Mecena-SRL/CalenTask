import SwiftUI
import SwiftData

/// Il menu contestuale unico delle attività (D46): stesso click destro,
/// stesse azioni, ovunque — righe, card, blocchi, barre del Gantt.
struct TaskMenuContent: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    @Environment(\.openURL) private var openURL

    var body: some View {
        // S5 — Partecipa: la videochiamata a un tap, ovunque sia la task.
        if let url = task.videoCallURL {
            Button {
                openURL(url)
            } label: {
                Label("Partecipa alla videochiamata", systemImage: "video.fill")
            }
        }

        Button {
            withAnimation(.dsSoft) { task.toggleDone() }
        } label: {
            Label(task.isDone ? "Riapri" : "Completa",
                  systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
        }

        Menu {
            Button("Oggi") { task.setDue(.now.startOfDay) }
            Button("Domani") {
                task.setDue(Calendar.app.date(byAdding: .day, value: 1, to: .now.startOfDay))
            }
            Button("Tra una settimana") {
                task.setDue(Calendar.app.date(byAdding: .day, value: 7, to: .now.startOfDay))
            }
            if task.dueAt != nil {
                Divider()
                Button("Rimuovi scadenza", role: .destructive) { task.setDue(nil) }
            }
        } label: {
            Label("Scadenza", systemImage: "flag")
        }

        Menu {
            Picker("Stato", selection: Binding(
                get: { task.status },
                set: { task.setStatus($0) }
            )) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
        } label: {
            Label("Stato", systemImage: "circle.lefthalf.filled")
        }

        Menu {
            Picker("Priorità", selection: Binding(
                get: { task.priority },
                set: { task.priority = $0; task.touch() }
            )) {
                ForEach(TaskPriority.allCases.reversed()) { level in
                    Label(level.label, systemImage: "flag.fill").tag(level)
                }
            }
        } label: {
            Label("Priorità", systemImage: "flag.circle")
        }

        Menu {
            Picker("Assegna a", selection: Binding(
                get: { task.assigneeID },
                set: { task.assigneeID = $0; task.touch() }
            )) {
                Text("Nessuno").tag(nil as UUID?)
                ForEach(people, id: \.id) { person in
                    Text(person.name).tag(person.id as UUID?)
                }
            }
        } label: {
            Label("Assegna a", systemImage: "person.crop.circle.badge.checkmark")
        }

        if !task.isPhase, let project = task.project {
            let stages = allStages.filter { $0.projectID == project.id }
            if !stages.isEmpty {
                Menu {
                    Picker("Stage", selection: Binding(
                        get: { task.stageID },
                        set: { newID in task.move(toStage: stages.first { $0.id == newID }) }
                    )) {
                        Text("Da smistare").tag(nil as UUID?)
                        ForEach(stages, id: \.id) { stage in
                            Text(stage.name).tag(stage.id as UUID?)
                        }
                    }
                } label: {
                    Label("Stage pipeline", systemImage: "arrow.right.square")
                }
            }
            if !project.phaseTasks.isEmpty {
                Menu {
                    Picker("Fase", selection: Binding(
                        get: { task.parentTask?.isPhase == true ? task.parentTask?.id : nil },
                        set: { newID in
                            task.parentTask = project.phaseTasks.first { $0.id == newID }
                            task.touch()
                        }
                    )) {
                        Text("Nessuna").tag(nil as UUID?)
                        ForEach(project.phaseTasks, id: \.id) { phase in
                            Text(phase.title).tag(phase.id as UUID?)
                        }
                    }
                } label: {
                    Label("Fase", systemImage: "square.stack.3d.up")
                }
            }
        }

        if !task.isPhase {
            Menu {
                Button("Inbox (nessun progetto)") { task.move(to: nil) }
                Divider()
                // A3 (audit account): il picker resta nello stesso spazio
                // dell'attività — spostare tra spazi lascerebbe workspaceID
                // disallineato dal progetto. Un trasferimento vero è un'altra
                // azione, non ancora implementata.
                ForEach(projects.filter { $0.workspaceID == task.workspaceID }, id: \.id) { project in
                    Button(project.name) { task.move(to: project) }
                }
            } label: {
                Label("Sposta in", systemImage: "folder")
            }
        }

        Divider()

        Button {
            try? TemplateService.duplicate(task, in: modelContext)
        } label: {
            Label("Duplica", systemImage: "plus.square.on.square")
        }
        Button {
            try? TemplateService.makeTemplate(from: task, in: modelContext)
        } label: {
            Label("Salva come modello", systemImage: "square.on.square.dashed")
        }

        Divider()

        Button(role: .destructive) {
            withAnimation {
                if task.isPhase {
                    task.softDeleteSubtree()
                } else {
                    task.softDelete()
                }
            }
        } label: {
            Label("Elimina", systemImage: "trash")
        }
    }
}

extension View {
    /// Attacca il menu contestuale standard delle attività (D46).
    func taskContextMenu(_ task: TodoTask) -> some View {
        contextMenu { TaskMenuContent(task: task) }
    }
}
