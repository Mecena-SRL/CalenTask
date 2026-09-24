import SwiftUI
import SwiftData

/// Definizione dei campi gestionali (D32): per progetto o per tutto lo
/// spazio. Tipi: testo, numero, data, scelta, spunta, link.
/// Esempi Mécena: Cliente, Fattura, Margine, Stato approvazione.
struct CustomFieldsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @Query(filter: #Predicate<CustomFieldDefinition> { $0.deletedAt == nil },
           sort: \CustomFieldDefinition.sortOrder)
    private var allDefinitions: [CustomFieldDefinition]

    @State private var newName = ""
    @State private var newType: CustomFieldType = .text
    @State private var newIsWorkspaceWide = false

    private var projectFields: [CustomFieldDefinition] {
        allDefinitions.filter { $0.projectID == project.id }
    }

    private var workspaceFields: [CustomFieldDefinition] {
        allDefinitions.filter { $0.projectID == nil && $0.workspaceID == project.workspaceID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !projectFields.isEmpty {
                    Section("Campi del progetto") {
                        ForEach(projectFields, id: \.id) { field in
                            FieldDefinitionRow(field: field)
                        }
                    }
                }
                if !workspaceFields.isEmpty {
                    Section("Campi dello spazio (tutti i progetti)") {
                        ForEach(workspaceFields, id: \.id) { field in
                            FieldDefinitionRow(field: field)
                        }
                    }
                }

                Section("Nuovo campo") {
                    DSPromptField(prompt: "Nome (es. Cliente, Fattura, Margine)",
                                  text: $newName)
                    Picker("Tipo", selection: $newType) {
                        ForEach(CustomFieldType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    }
                    Toggle("Per tutto lo spazio", isOn: $newIsWorkspaceWide)
                    Button("Aggiungi campo", action: addField)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Campi · \(project.name)")
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
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }

    private func addField() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let siblings = newIsWorkspaceWide ? workspaceFields : projectFields
        modelContext.insert(CustomFieldDefinition(
            workspaceID: project.workspaceID,
            projectID: newIsWorkspaceWide ? nil : project.id,
            name: name,
            type: newType,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1
        ))
        newName = ""
        newType = .text
    }
}

private struct FieldDefinitionRow: View {
    @Bindable var field: CustomFieldDefinition
    @State private var newOption = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.m) {
                DSIconTile(systemImage: field.type.systemImage, tint: .indigo)
                TextField("Nome", text: Binding(
                    get: { field.name },
                    set: { field.name = $0; field.updatedAt = .now }
                ))
                .textFieldStyle(.plain)
                .font(.dsMeta)
                Spacer()
                Text(field.type.label)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    withAnimation { field.deletedAt = .now; field.updatedAt = .now }
                } label: {
                    Image(systemName: "trash")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if field.type == .select {
                HStack(spacing: DS.s) {
                    ForEach(field.options, id: \.self) { option in
                        HStack(spacing: 2) {
                            Text(option)
                            Button {
                                field.options.removeAll { $0 == option }
                                field.updatedAt = .now
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.dsCaption)
                        .padding(.horizontal, DS.s)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.indigo)
                    }
                    TextField("Opzione…", text: $newOption)
                        .textFieldStyle(.plain)
                        .font(.dsCaption)
                        .frame(minWidth: 70)
                        .onSubmit {
                            let option = newOption.trimmingCharacters(in: .whitespaces)
                            guard !option.isEmpty, !field.options.contains(option) else { return }
                            field.options.append(option)
                            field.updatedAt = .now
                            newOption = ""
                        }
                }
                .padding(.leading, 40)
            }
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return CustomFieldsEditorView(project: preview.project)
        .modelContainer(preview.container)
}
