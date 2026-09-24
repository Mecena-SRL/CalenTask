import SwiftUI
import SwiftData

/// Crea o modifica uno spazio di lavoro (D49): nome, colore dalla palette,
/// preset di partenza. Si parte da zero — i preset suggeriscono, non impongono.
struct WorkspaceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creazione; valorizzato = modifica.
    var workspace: Workspace?

    @State private var name = ""
    @State private var colorHex = DSPalette.swatches[4].hex
    @State private var didLoad = false

    private struct Preset: Identifiable {
        let id: String
        let label: String
        let systemImage: String
        let colorHex: String
    }

    private let presets: [Preset] = [
        Preset(id: "company", label: "Società", systemImage: "building.2", colorHex: "#3E63DD"),
        Preset(id: "production", label: "Produzione video", systemImage: "film", colorHex: "#E5484D"),
        Preset(id: "studio", label: "Studio creativo", systemImage: "paintpalette", colorHex: "#D6409F"),
        Preset(id: "team", label: "Team", systemImage: "person.3", colorHex: "#30A46C"),
    ]

    private var isEditing: Bool { workspace != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: DS.m) {
                        Circle()
                            .fill(Color(hex: colorHex).gradient)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        TextField("Nome dello spazio", text: $name)
                            .font(.dsRowTitle)
                            .textFieldStyle(.plain)
                    }
                    .padding(.vertical, DS.xs)
                }

                Section("Colore") {
                    DSPaletteGrid(selectedHex: $colorHex)
                        .padding(.vertical, DS.xs)
                }

                if !isEditing {
                    Section("Parti da un'idea") {
                        ForEach(presets) { preset in
                            Button {
                                withAnimation(.dsQuick) {
                                    if name.isEmpty { name = preset.label }
                                    colorHex = preset.colorHex
                                }
                            } label: {
                                Label(preset.label, systemImage: preset.systemImage)
                                    .foregroundStyle(Color(hex: preset.colorHex))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Modifica spazio" : "Nuovo spazio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Crea") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !didLoad, let workspace else { return }
                didLoad = true
                name = workspace.name
                colorHex = workspace.colorHex
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 460)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            if let workspace {
                workspace.name = trimmed
                workspace.colorHex = colorHex
                workspace.updatedAt = .now
                try modelContext.save()
            } else {
                let created = try SeedService.createWorkspace(
                    name: trimmed, colorHex: colorHex, in: modelContext
                )
                // Il nuovo spazio diventa subito lo scope attivo.
                UserDefaults.standard.set(
                    created.id.uuidString, forKey: WorkspaceScope.storageKey
                )
            }
            dismiss()
        } catch {
            assertionFailure("Workspace save failed: \(error)")
        }
    }
}

/// La sezione "Spazi" delle Impostazioni: gestione completa, Apple-style.
struct WorkspacesSettingsSection: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil },
           sort: \Workspace.createdAt)
    private var workspaces: [Workspace]

    @Query(filter: #Predicate<TodoTask> { $0.deletedAt == nil })
    private var allTasks: [TodoTask]

    @State private var editing: Workspace?
    @State private var isCreating = false

    var body: some View {
        Section {
            ForEach(workspaces, id: \.id) { workspace in
                HStack(spacing: DS.m) {
                    Circle()
                        .fill(Color(hex: workspace.colorHex).gradient)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: workspace.isPersonal ? "person.fill" : "building.2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(workspace.name)
                            .font(.dsMeta.weight(.medium))
                        Text(workspace.isPersonal
                             ? "Spazio personale"
                             : "\(taskCount(in: workspace)) attività")
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Modifica") { editing = workspace }
                        .font(.dsCaption)
                        .buttonStyle(.borderless)
                    if !workspace.isPersonal {
                        Button(role: .destructive) {
                            delete(workspace)
                        } label: {
                            Image(systemName: "trash")
                                .font(.dsCaption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(taskCount(in: workspace) > 0)
                        .help(taskCount(in: workspace) > 0
                              ? "Sposta o completa le attività prima di eliminare"
                              : "Elimina spazio")
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                isCreating = true
            } label: {
                Label("Nuovo spazio…", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Spazi di lavoro")
        } footer: {
            Text("Gli spazi separano la vita personale dal lavoro: la tua società, un team, un cliente. Ogni progetto e attività vive in uno spazio.")
                .font(.dsCaption)
        }
        .sheet(item: $editing) { workspace in
            WorkspaceEditorView(workspace: workspace)
        }
        .sheet(isPresented: $isCreating) {
            WorkspaceEditorView()
        }
    }

    private func taskCount(in workspace: Workspace) -> Int {
        allTasks.filter { $0.workspaceID == workspace.id }.count
    }

    private func delete(_ workspace: Workspace) {
        guard taskCount(in: workspace) == 0 else { return }
        withAnimation(.dsSoft) {
            workspace.deletedAt = .now
            workspace.updatedAt = .now
            if UserDefaults.standard.string(forKey: WorkspaceScope.storageKey)
                == workspace.id.uuidString {
                UserDefaults.standard.set("all", forKey: WorkspaceScope.storageKey)
            }
        }
    }
}

#Preview {
    WorkspaceEditorView()
        .modelContainer(PreviewSampleData.make().container)
}
