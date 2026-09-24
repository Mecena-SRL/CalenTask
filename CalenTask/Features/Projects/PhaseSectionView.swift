import SwiftUI
import SwiftData

/// One phase of a project — the phase IS a task of kind .phase (D5):
/// header with aggregated progress, children, inline quick-add.
struct PhaseSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var phase: TodoTask
    let project: Project
    /// G5 — la fase si riduce dal suo header.
    var isCollapsed = false
    var onToggleCollapse: () -> Void = {}

    @State private var newTaskTitle = ""

    /// F35 — il colore della fase separa i blocchi a colpo d'occhio.
    private var tint: Color {
        phase.colorHex.isEmpty ? Color(hex: project.colorHex) : Color(hex: phase.colorHex)
    }

    var body: some View {
        Section {
            if !isCollapsed {
                ForEach(liveTasks, id: \.id) { task in
                    TaskOpenLink(task: task) {
                        TaskRow(task: task, showProject: false) {
                            withAnimation(.dsSoft) { task.toggleDone() }
                        }
                    }
                    .taskContextMenu(task)
                    .listRowBackground(tint.opacity(0.045))
                }
                HStack(spacing: DS.m) {
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                    DSPromptField(prompt: "Aggiungi a \(phase.title)", text: $newTaskTitle)
                        .onSubmit(addTask)
                }
                .listRowBackground(tint.opacity(0.045))
            }
        } header: {
            HStack(spacing: DS.s) {
                // G5 — il chevron di riduzione, prima della pill.
                Button(action: onToggleCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Espandi la fase" : "Riduci la fase")
                // La pill colorata della fase: stesso linguaggio della Bacheca.
                Text(phase.title)
                    .font(.dsCaption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.s + 2)
                    .padding(.vertical, 3)
                    .background(tint.gradient, in: Capsule())
                    .lineLimit(1)
                if !liveTasks.isEmpty {
                    Text("\(doneCount)/\(liveTasks.count)")
                        .font(.dsNumeric)
                        .foregroundStyle(.secondary)
                    ProgressView(value: phase.aggregatedProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 56)
                        .tint(tint)
                }
                Spacer()
                Menu {
                    Picker("Stato fase", selection: statusBinding) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    Divider()
                    Button("Elimina fase", role: .destructive) {
                        withAnimation { phase.softDeleteSubtree() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var liveTasks: [TodoTask] {
        phase.liveSubtasks.filter { !$0.isTemplate }
    }

    private var doneCount: Int { liveTasks.filter(\.isDone).count }

    private var statusBinding: Binding<TaskStatus> {
        Binding(get: { phase.status }, set: { phase.setStatus($0) })
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = TodoTask(
            workspaceID: project.workspaceID,
            title: title,
            sortOrder: (liveTasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: project.createdByID
        )
        modelContext.insert(task)
        task.project = project
        task.parentTask = phase
        newTaskTitle = ""
    }
}
