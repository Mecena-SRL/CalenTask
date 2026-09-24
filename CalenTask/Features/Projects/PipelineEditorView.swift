import SwiftUI
import SwiftData

/// Editor della pipeline di progetto (D29): stage ordinati, colorati,
/// rinominabili; l'ultimo terminale chiude il flusso (es. "Archivio").
struct PipelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    @State private var newStageName = ""

    private var stages: [WorkflowStage] {
        allStages.filter { $0.projectID == project.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if stages.isEmpty {
                    Section {
                        Text("Nessuna pipeline: le attività usano gli stati base. Aggiungi il primo stage per creare il flusso di lavorazione (es. Preventivo → Conferma → … → Archivio).")
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(stages, id: \.id) { stage in
                    StageRow(
                        stage: stage,
                        isFirst: stage.id == stages.first?.id,
                        isLast: stage.id == stages.last?.id,
                        onMoveUp: { move(stage, by: -1) },
                        onMoveDown: { move(stage, by: 1) }
                    )
                }

                Section {
                    HStack {
                        Image(systemName: "plus")
                            .foregroundStyle(.tertiary)
                        TextField("Nuovo stage", text: $newStageName)
                            .onSubmit(addStage)
                        Button("Aggiungi", action: addStage)
                            .disabled(newStageName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Pipeline · \(project.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func addStage() {
        let name = newStageName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let order = (stages.map(\.order).max() ?? -1) + 1
        modelContext.insert(WorkflowStage(
            workspaceID: project.workspaceID,
            projectID: project.id,
            name: name,
            order: order,
            colorHex: WorkflowStage.defaultColor(forOrder: order)
        ))
        newStageName = ""
    }

    private func move(_ stage: WorkflowStage, by delta: Int) {
        let ordered = stages
        guard let index = ordered.firstIndex(where: { $0.id == stage.id }) else { return }
        let target = index + delta
        guard ordered.indices.contains(target) else { return }
        withAnimation(.dsQuick) {
            let other = ordered[target]
            swap(&stage.order, &other.order)
            stage.updatedAt = .now
            other.updatedAt = .now
        }
    }
}

private struct StageRow: View {
    @Bindable var stage: WorkflowStage
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: DS.m) {
            Menu {
                ForEach(DSPalette.swatches) { swatch in
                    Button {
                        stage.colorHex = swatch.hex
                        stage.updatedAt = .now
                    } label: {
                        Label {
                            Text(swatch.name)
                        } icon: {
                            Image(systemName: swatch.hex == stage.colorHex
                                  ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(swatch.color)
                        }
                    }
                }
            } label: {
                // Monday-style pill: the stage IS its color.
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: stage.colorHex))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField("Nome", text: Binding(
                get: { stage.name },
                set: { stage.name = $0; stage.updatedAt = .now }
            ))
            .textFieldStyle(.plain)
            .font(.dsMeta)

            Spacer()

            Toggle(isOn: Binding(
                get: { stage.isTerminal },
                set: { stage.isTerminal = $0; stage.updatedAt = .now }
            )) {
                Image(systemName: "flag.checkered")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(stage.isTerminal ? Color.accentColor : Color.secondary)
            .help("Stage terminale (chiude la pipeline)")

            VStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(isFirst)
                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(isLast)
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button(role: .destructive) {
                withAnimation {
                    stage.deletedAt = .now
                    stage.updatedAt = .now
                }
            } label: {
                Image(systemName: "trash")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return PipelineEditorView(project: preview.project)
        .modelContainer(preview.container)
}
