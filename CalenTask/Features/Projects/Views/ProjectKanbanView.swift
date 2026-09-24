import SwiftUI
import SwiftData

/// Kanban (D8/D29): one column per pipeline stage when the project has a
/// custom workflow, otherwise per plain status. Cards drag between columns.
struct ProjectKanbanView: View {
    @Bindable var project: Project

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    private var stages: [WorkflowStage] {
        allStages.filter { $0.projectID == project.id }
    }

    @State private var showsPipeline = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.l) {
                if stages.isEmpty {
                    // No pipeline → classic status board.
                    ForEach(TaskStatus.allCases) { status in
                        KanbanColumn(
                            mode: .status(status),
                            tasks: tasks(in: status),
                            project: project
                        )
                    }
                } else {
                    // Pipeline board (D29): the project's own workflow.
                    KanbanColumn(
                        mode: .unstaged,
                        tasks: unstagedTasks,
                        project: project
                    )
                    ForEach(stages, id: \.id) { stage in
                        KanbanColumn(
                            mode: .stage(stage),
                            tasks: tasks(in: stage),
                            project: project,
                            onHeaderTap: { showsPipeline = true }
                        )
                    }
                }
            }
            .padding(DS.l)
        }
        .background(DSColor.surfaceSecondary)
        .sheet(isPresented: $showsPipeline) {
            PipelineEditorView(project: project)
        }
    }

    private var liveTasks: [TodoTask] {
        project.tasks.filter { $0.deletedAt == nil && !$0.isPhase && !$0.isTemplate }
    }

    private func tasks(in status: TaskStatus) -> [TodoTask] {
        liveTasks
            .filter { $0.status == status }
            .sorted { ($0.priorityRaw, $0.sortOrder) > ($1.priorityRaw, $1.sortOrder) }
    }

    private func tasks(in stage: WorkflowStage) -> [TodoTask] {
        liveTasks
            .filter { $0.stageID == stage.id }
            .sorted { ($0.priorityRaw, $0.sortOrder) > ($1.priorityRaw, $1.sortOrder) }
    }

    private var unstagedTasks: [TodoTask] {
        let stageIDs = Set(stages.map(\.id))
        return liveTasks
            .filter { task in
                guard let stageID = task.stageID else { return true }
                return !stageIDs.contains(stageID)
            }
            .filter { !$0.isDone }
            .sorted { ($0.priorityRaw, $0.sortOrder) > ($1.priorityRaw, $1.sortOrder) }
    }
}

private struct KanbanColumn: View {
    enum Mode {
        case status(TaskStatus)
        case stage(WorkflowStage)
        case unstaged

        var title: String {
            switch self {
            case .status(let status): status.label
            case .stage(let stage): stage.name
            case .unstaged: "Da smistare"
            }
        }

        var tint: Color {
            switch self {
            case .status(let status): DSColor.status(status)
            case .stage(let stage): Color(hex: stage.colorHex)
            case .unstaged: .secondary
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    let mode: Mode
    let tasks: [TodoTask]
    let project: Project

    @State private var isDropTarget = false
    @State private var newTitle = ""
    /// G12 — la card sopra cui sto passando col drag.
    @State private var insertTargetID: UUID?

    /// F37 — il tap sull'header di uno stage apre l'editor della pipeline.
    var onHeaderTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            // Monday-style colored header pill.
            HStack(spacing: DS.s) {
                Button {
                    onHeaderTap?()
                } label: {
                    Text(mode.title)
                        .font(.dsCaption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.s + 2)
                        .padding(.vertical, 3)
                        .background(mode.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(onHeaderTap == nil)
                .help(onHeaderTap == nil ? "" : "Modifica la pipeline")
                Text("\(tasks.count)")
                    .font(.dsNumeric)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, DS.xs)

            ScrollView {
                VStack(spacing: DS.s) {
                    ForEach(tasks, id: \.id) { task in
                        // G7 — su Mac la card apre l'inspector, niente pagina.
                        TaskOpenLink(task: task) {
                            TaskCardView(task: task, showsStatus: isStatusMode == false)
                        }
                        .taskContextMenu(task)
                        .draggable(task.id.uuidString)
                        // G12 — drop su una card = inserisci prima di lei.
                        .overlay(alignment: .top) {
                            if insertTargetID == task.id {
                                Capsule()
                                    .fill(mode.tint)
                                    .frame(height: 3)
                                    .offset(y: -(DS.s / 2 + 1.5))
                                    .transition(.opacity)
                            }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            insertTargetID = nil
                            return handleDrop(items, before: task)
                        } isTargeted: { hovering in
                            withAnimation(.dsQuick) {
                                if hovering {
                                    insertTargetID = task.id
                                } else if insertTargetID == task.id {
                                    insertTargetID = nil
                                }
                            }
                        }
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .padding(DS.xs)
                .animation(.dsSoft, value: tasks.map(\.id))
            }

            // Creazione direttamente nella colonna (D41). G6 — campo pulito.
            HStack(spacing: DS.s) {
                Image(systemName: "plus")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
                TextField("", text: $newTitle, prompt: Text("Aggiungi"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.dsMeta)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, DS.m)
            .frame(height: 32)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(DSColor.hairline)
            }
        }
        .padding(DS.s)
        .frame(width: 280)
        // F37 — anche qui la colonna respira il colore del suo stage.
        .background(
            mode.tint.opacity(isDropTarget ? 0.12 : 0.05),
            in: RoundedRectangle(cornerRadius: DS.Radius.medium)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.medium,
                topTrailingRadius: DS.Radius.medium
            )
            .fill(mode.tint)
            .frame(height: 3)
        }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { isDropTarget = $0 }
    }

    private var isStatusMode: Bool {
        if case .status = mode { return true }
        return false
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = TodoTask(
            workspaceID: project.workspaceID,
            title: title,
            sortOrder: (tasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: project.createdByID
        )
        modelContext.insert(task)
        task.project = project
        switch mode {
        case .status(let status):
            task.status = status
        case .stage(let stage):
            task.stageID = stage.id
        case .unstaged:
            break
        }
        newTitle = ""
    }

    private func handleDrop(_ items: [String], before target: TodoTask? = nil) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == id })
        guard let task = try? modelContext.fetch(descriptor).first,
              task.id != target?.id else { return false }
        withAnimation(.dsSoft) {
            switch mode {
            case .status(let status):
                task.setStatus(status)
            case .stage(let stage):
                task.move(toStage: stage)
            case .unstaged:
                task.move(toStage: nil)
            }
            // G12 — inserimento in mezzo (la colonna ordina per sortOrder
            // decrescente a parità di priorità).
            var order = tasks.filter { $0.id != task.id }
            if let target, let index = order.firstIndex(where: { $0.id == target.id }) {
                order.insert(task, at: index)
            } else {
                order.append(task)
            }
            for (index, sibling) in order.enumerated() {
                let newOrder = order.count - index
                if sibling.sortOrder != newOrder {
                    sibling.sortOrder = newOrder
                }
            }
        }
        return true
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        ProjectKanbanView(project: preview.project)
    }
    .modelContainer(preview.container)
}
