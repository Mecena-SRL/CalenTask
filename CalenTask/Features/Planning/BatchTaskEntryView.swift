import SwiftUI
import SwiftData

/// Paste or type one task per line; confirm creates them all in one transaction.
struct BatchTaskEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var project: Project
    var preferredPhaseID: UUID?

    @State private var text = ""
    @State private var selectedPhaseID: UUID?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.m) {
                if !project.phaseTasks.isEmpty {
                    Picker("Fase di destinazione", selection: $selectedPhaseID) {
                        Text("Senza fase").tag(nil as UUID?)
                        ForEach(project.phaseTasks, id: \.id) { phase in
                            Text(phase.title).tag(phase.id as UUID?)
                        }
                    }
                }

                TextEditor(text: $text)
                    .font(.dsMeta)
                    .frame(minHeight: 220)
                    .padding(DS.s)
                    .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.small))

                Text("Una attività per riga. \(lines.count) da creare.")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.l)
            .navigationTitle("Inserimento multiplo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea \(lines.count)") { createAll() }
                        .disabled(lines.isEmpty)
                }
            }
            .onAppear { selectedPhaseID = preferredPhaseID }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private var lines: [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func createAll() {
        let phase = project.phaseTasks.first { $0.id == selectedPhaseID }
        let siblings = phase?.liveSubtasks ?? project.unphasedTasks
        let baseOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        for (index, title) in lines.enumerated() {
            let task = TodoTask(
                workspaceID: project.workspaceID,
                title: title,
                sortOrder: baseOrder + index,
                createdByID: project.createdByID
            )
            modelContext.insert(task)
            task.project = project
            task.parentTask = phase
            TagService.syncTags(for: task, in: modelContext)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            assertionFailure("Batch entry failed: \(error)")
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return BatchTaskEntryView(project: preview.project)
        .modelContainer(preview.container)
}
