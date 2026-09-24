import SwiftUI
import SwiftData

/// Bacheca (D8): one column per phase + "Senza fase". Cards drag between
/// columns to change phase; quick-add at the bottom of each column.
struct ProjectBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.l) {
                ForEach(project.phaseTasks, id: \.id) { phase in
                    BoardColumn(
                        title: phase.title,
                        subtitle: progressLabel(for: phase),
                        tint: phase.colorHex.isEmpty
                            ? Color(hex: project.colorHex) : Color(hex: phase.colorHex),
                        tasks: phase.liveSubtasks.filter { !$0.isTemplate && !$0.isPhase },
                        project: project,
                        destinationPhase: phase
                    )
                }
                BoardColumn(
                    title: "Senza fase",
                    subtitle: nil,
                    tint: .secondary,
                    tasks: project.unphasedTasks,
                    project: project,
                    destinationPhase: nil
                )

                newPhaseColumn
            }
            .padding(DS.l)
        }
        .background(DSColor.surfaceSecondary)
    }

    @State private var newPhaseName = ""

    /// Le fasi nascono anche da qui (D41). G6 — stesso campo pulito.
    private var newPhaseColumn: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.s) {
                Image(systemName: "plus")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
                TextField("", text: $newPhaseName, prompt: Text("Nuova fase"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.dsMeta.weight(.medium))
                    .onSubmit(addPhase)
            }
            .padding(.horizontal, DS.m)
            .frame(height: 32)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(DSColor.hairline)
            }
            Spacer()
        }
        .padding(DS.s)
        .frame(width: 220)
    }

    private func addPhase() {
        let name = newPhaseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let phase = TodoTask(
            workspaceID: project.workspaceID,
            title: name,
            kind: .phase,
            sortOrder: (project.phaseTasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: project.createdByID
        )
        modelContext.insert(phase)
        phase.project = project
        newPhaseName = ""
    }

    private func progressLabel(for phase: TodoTask) -> String? {
        let children = phase.liveSubtasks.filter { !$0.isTemplate }
        guard !children.isEmpty else { return nil }
        return "\(children.filter(\.isDone).count)/\(children.count)"
    }
}

private struct BoardColumn: View {
    @Environment(\.modelContext) private var modelContext
    let title: String
    let subtitle: String?
    let tint: Color
    let tasks: [TodoTask]
    let project: Project
    /// nil ⇒ the "Senza fase" column (drops clear the parent).
    let destinationPhase: TodoTask?

    @State private var newTitle = ""
    @State private var isDropTarget = false
    @State private var isRenaming = false
    @State private var renameText = ""
    /// G12 — la card sopra cui sto passando col drag: lì entra l'elemento.
    @State private var insertTargetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            // Monday-style colored header pill. F36: il tap apre la fase
            // (inspector su Mac, push su iOS).
            HStack(spacing: DS.s) {
                if let phase = destinationPhase {
                    TaskOpenLink(task: phase) {
                        headerPill
                    }
                    .help("Apri la fase")
                } else {
                    headerPill
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.dsNumeric)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, DS.xs)
            .contentShape(Rectangle())
            // D57: la fase si rinomina, si colora e si sposta da qui.
            .contextMenu {
                if let phase = destinationPhase {
                    Button {
                        renameText = phase.title
                        isRenaming = true
                    } label: {
                        Label("Rinomina…", systemImage: "pencil")
                    }
                    Menu {
                        Button("Colore del progetto") {
                            phase.colorHex = ""
                            phase.touch()
                        }
                        ForEach(DSPalette.swatches) { swatch in
                            Button {
                                phase.colorHex = swatch.hex
                                phase.touch()
                            } label: {
                                Label {
                                    Text(swatch.name)
                                } icon: {
                                    Image(systemName: phase.colorHex == swatch.hex
                                          ? "checkmark.circle.fill" : "circle.fill")
                                }
                            }
                            .tint(swatch.color)
                        }
                    } label: {
                        Label("Colore fase", systemImage: "paintpalette")
                    }
                    Button {
                        movePhase(phase, by: -1)
                    } label: {
                        Label("Sposta a sinistra", systemImage: "arrow.left")
                    }
                    Button {
                        movePhase(phase, by: 1)
                    } label: {
                        Label("Sposta a destra", systemImage: "arrow.right")
                    }
                }
            }
            .alert("Rinomina fase", isPresented: $isRenaming) {
                TextField("Nome", text: $renameText)
                Button("Annulla", role: .cancel) {}
                Button("Salva") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    if let phase = destinationPhase, !trimmed.isEmpty {
                        phase.title = trimmed
                        phase.touch()
                    }
                }
            }

            ScrollView {
                VStack(spacing: DS.s) {
                    ForEach(tasks, id: \.id) { task in
                        // G7 — su Mac la card apre l'inspector, niente pagina.
                        TaskOpenLink(task: task) {
                            TaskCardView(task: task) {
                                withAnimation(.dsSoft) { task.toggleDone() }
                            }
                        }
                        .taskContextMenu(task)
                        .draggable(task.id.uuidString)
                        // G12 — drop SU una card = inserisci prima di lei,
                        // con la linea d'inserimento che lo racconta.
                        .overlay(alignment: .top) {
                            if insertTargetID == task.id {
                                Capsule()
                                    .fill(tint)
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
                // G12 — gli spostamenti si vedono: niente scatti secchi.
                .animation(.dsSoft, value: tasks.map(\.id))
            }

            // G6 — campo aggiungi pulito: superficie piena, bordo, niente
            // doppi sfondi semitrasparenti che sporcavano il wash colorato.
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
        // F36 — la colonna respira il colore della sua fase.
        .background(
            tint.opacity(isDropTarget ? 0.12 : 0.05),
            in: RoundedRectangle(cornerRadius: DS.Radius.medium)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Radius.medium,
                topTrailingRadius: DS.Radius.medium
            )
            .fill(tint)
            .frame(height: 3)
        }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { isDropTarget = $0 }
    }

    private var headerPill: some View {
        Text(title)
            .font(.dsCaption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.s + 2)
            .padding(.vertical, 3)
            .background(tint.gradient, in: Capsule())
            .lineLimit(1)
    }

    /// Scambia l'ordine con la fase adiacente (D57: il "numero" della fase).
    private func movePhase(_ phase: TodoTask, by delta: Int) {
        let phases = project.phaseTasks
        guard let index = phases.firstIndex(where: { $0.id == phase.id }) else { return }
        let target = index + delta
        guard phases.indices.contains(target) else { return }
        withAnimation(.dsQuick) {
            let other = phases[target]
            let mine = phase.sortOrder
            phase.sortOrder = other.sortOrder
            other.sortOrder = mine
            phase.touch()
            other.touch()
        }
    }

    private func handleDrop(_ items: [String], before target: TodoTask? = nil) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        guard let task = fetchTask(id), !task.isPhase, task.id != target?.id
        else { return false }
        withAnimation(.dsSoft) {
            task.project = project
            task.parentTask = destinationPhase
            // G12 — inserimento in mezzo: i fratelli si rinumerano attorno.
            var order = tasks.filter { $0.id != task.id }
            if let target, let index = order.firstIndex(where: { $0.id == target.id }) {
                order.insert(task, at: index)
            } else {
                order.append(task)
            }
            for (index, sibling) in order.enumerated() where sibling.sortOrder != index {
                sibling.sortOrder = index
            }
            task.touch()
        }
        return true
    }

    private func fetchTask(_ id: UUID) -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
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
        task.parentTask = destinationPhase
        newTitle = ""
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        ProjectBoardView(project: preview.project)
    }
    .modelContainer(preview.container)
}
