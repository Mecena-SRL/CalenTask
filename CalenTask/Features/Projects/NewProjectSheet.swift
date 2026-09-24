import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    @State private var name = ""
    @State private var selectedTemplate: ProjectTemplate = TemplateCatalog.empty
    @State private var colorHex = TemplateCatalog.empty.suggestedColorHex
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DSPromptField(prompt: "Nome del progetto", text: $name)
                        .focused($isNameFocused)
                    // La palette vivida condivisa (D48).
                    DSPaletteGrid(selectedHex: $colorHex)
                        .padding(.vertical, DS.xs)
                }

                ForEach(TemplateCategory.allCases) { category in
                    let templates = TemplateCatalog.templates(in: category)
                    if !templates.isEmpty {
                        Section(category.label) {
                            ForEach(templates) { template in
                                templateRow(template)
                            }
                        }
                    }
                }

                if !selectedTemplate.phases.isEmpty {
                    Section("Fasi incluse") {
                        ForEach(Array(selectedTemplate.phases.enumerated()), id: \.offset) { index, phase in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.dsNumeric)
                                    .foregroundStyle(.secondary)
                                Text(phase.name)
                                Spacer()
                                Text("\(phase.starterTasks.count) attività")
                                    .font(.dsCaption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nuovo progetto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func templateRow(_ template: ProjectTemplate) -> some View {
        Button {
            selectedTemplate = template
            colorHex = template.suggestedColorHex
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(template.name)
                        .font(.dsRowTitle)
                        .foregroundStyle(.primary)
                    Text(template.summary)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: template.id == selectedTemplate.id
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(template.id == selectedTemplate.id
                                     ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func create() {
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let target = WorkspaceScope.creationTarget(raw: scopeRaw, workspaces: workspaces) ?? workspace
            try TemplateService.apply(
                selectedTemplate,
                projectName: name.trimmingCharacters(in: .whitespaces),
                colorHex: colorHex,
                workspaceID: target.id,
                createdBy: me.id,
                in: modelContext
            )
            dismiss()
        } catch {
            assertionFailure("Project creation failed: \(error)")
        }
    }
}

#Preview {
    NewProjectSheet()
        .modelContainer(PreviewSampleData.make().container)
}
