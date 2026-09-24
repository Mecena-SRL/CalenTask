import SwiftUI
import SwiftData

/// "Sit down and plan" mode: rapid serial entry of many tasks across phases.
/// Phases are tasks of kind .phase (D5).
/// macOS: one column per phase. iOS: phase picker + rapid-entry list.
struct PhasePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project
    @State private var showsBatchEntry = false
    @State private var selectedPhaseID: UUID?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pianifica · \(project.name)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Chiudi") { dismiss() }
                    }
                    ToolbarItem {
                        Button {
                            showsBatchEntry = true
                        } label: {
                            Label("Inserimento multiplo", systemImage: "text.append")
                        }
                    }
                }
                .sheet(isPresented: $showsBatchEntry) {
                    BatchTaskEntryView(project: project, preferredPhaseID: selectedPhaseID)
                }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.l) {
                ForEach(project.phaseTasks, id: \.id) { phase in
                    PlannerColumn(phase: phase, project: project)
                        .frame(width: 280)
                }
            }
            .padding(DS.l)
        }
        #else
        VStack(spacing: 0) {
            if project.phaseTasks.count > 1 {
                Picker("Fase", selection: $selectedPhaseID) {
                    ForEach(project.phaseTasks, id: \.id) { phase in
                        Text(phase.title).tag(phase.id as UUID?)
                    }
                }
                .pickerStyle(.segmented)
                .padding(DS.l)
            }
            if let phase = currentPhase {
                PlannerColumn(phase: phase, project: project)
                    .padding(.horizontal, DS.l)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            if selectedPhaseID == nil { selectedPhaseID = project.phaseTasks.first?.id }
        }
        #endif
    }

    private var currentPhase: TodoTask? {
        project.phaseTasks.first { $0.id == selectedPhaseID } ?? project.phaseTasks.first
    }
}

/// One phase column: sticky quick-add on top, then the open tasks.
private struct PlannerColumn: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var phase: TodoTask
    let project: Project

    @State private var newTitle = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: phase.title, count: liveTasks.count)

            HStack {
                Image(systemName: "plus")
                    .foregroundStyle(.tertiary)
                TextField("Aggiungi e premi Invio", text: $newTitle)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        addTask()
                        isFocused = true   // serial entry: type, Return, type, Return
                    }
            }
            .padding(DS.m)
            .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.small))

            ScrollView {
                VStack(spacing: DS.xs) {
                    ForEach(liveTasks, id: \.id) { task in
                        TaskRow(task: task, showProject: false) {
                            withAnimation(.dsSoft) { task.toggleDone() }
                        }
                        .padding(.horizontal, DS.s)
                    }
                }
            }
        }
    }

    private var liveTasks: [TodoTask] {
        phase.liveSubtasks.filter { !$0.isTemplate }
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
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
        newTitle = ""
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return PhasePlannerView(project: preview.project)
        .modelContainer(preview.container)
}
