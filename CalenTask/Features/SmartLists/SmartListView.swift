import SwiftUI
import SwiftData

// MARK: - Matcher dei filtri (S4/D62)

extension SavedViewFilters {
    /// Tutti i criteri in AND; array vuoti = nessun vincolo.
    func matches(_ task: TodoTask) -> Bool {
        guard task.deletedAt == nil, !task.isTemplate, !task.isPhase else { return false }
        if !includeDone && task.isDone { return false }
        if !statuses.isEmpty && !statuses.contains(task.status) { return false }
        if !priorities.isEmpty && !priorities.contains(task.priority) { return false }
        if !kinds.isEmpty && !kinds.contains(task.kind) { return false }
        if !tagIDs.isEmpty {
            let taskTagIDs = Set(task.tags.filter { $0.deletedAt == nil }.map(\.id))
            if !tagIDs.contains(where: taskTagIDs.contains) { return false }
        }
        if let days = dueWithinDays {
            guard let dueAt = task.dueAt,
                  let limit = Calendar.current.date(
                    byAdding: .day, value: days + 1, to: .now.startOfDay)
            else { return false }
            if dueAt >= limit { return false }
        }
        return true
    }
}

// MARK: - Lista smart (S4/D62)

/// Una smart list salvata: i filtri di SavedView applicati dal vivo.
/// Destinazione di navigazione (D70): lo stack lo fornisce l'host
/// (detail su Mac/iPad, push dentro Sfoglia su iPhone).
struct SmartListView: View {
    @Bindable var savedView: SavedView

    @Query(filter: #Predicate<TodoTask> { $0.deletedAt == nil && !$0.isTemplate })
    private var allTasks: [TodoTask]

    @State private var isEditing = false

    private var tasks: [TodoTask] {
        let filters = savedView.filters
        return allTasks
            .filter { $0.workspaceID == savedView.workspaceID && filters.matches($0) }
            .sorted {
                ($0.dueAt ?? .distantFuture, $1.priorityRaw)
                    < ($1.dueAt ?? .distantFuture, $0.priorityRaw)
            }
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                DSEmptyState(
                    icon: "bookmark",
                    title: "Niente qui",
                    subtitle: "Nessuna attività corrisponde ai filtri di questa lista."
                )
            } else {
                List {
                    ForEach(tasks, id: \.id) { task in
                        TaskOpenLink(task: task) {
                            TaskRow(task: task) {
                                withAnimation(.dsSoft) { task.toggleDone() }
                            }
                        }
                        .taskContextMenu(task)
                    }
                }
            }
        }
        .navigationTitle(savedView.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    isEditing = true
                } label: {
                    Label("Modifica filtri", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            SmartListEditorView(savedView: savedView)
        }
    }
}

// MARK: - Editor (crea/modifica)

struct SmartListEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creazione.
    var savedView: SavedView?

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @State private var name = ""
    @State private var statuses: Set<TaskStatus> = []
    @State private var priorities: Set<TaskPriority> = []
    @State private var tagIDs: Set<UUID> = []
    @State private var dueWithinEnabled = false
    @State private var dueWithinDays = 7
    @State private var includeDone = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DSPromptField(prompt: "Nome della lista", text: $name)
                        .font(.dsRowTitle)
                }
                Section("Stato") {
                    chipToggles(TaskStatus.allCases, selection: $statuses) {
                        ($0.label, DSColor.status($0))
                    }
                }
                Section("Priorità") {
                    chipToggles(TaskPriority.allCases, selection: $priorities) {
                        ($0.label, DSColor.priority($0))
                    }
                }
                if !allTags.isEmpty {
                    Section("Etichette") {
                        chipToggles(allTags.map(\.id), selection: $tagIDs) { id in
                            let tag = allTags.first { $0.id == id }
                            return ("#\(tag?.name ?? "?")", Color(hex: tag?.colorHex ?? "#64748B"))
                        }
                    }
                }
                Section("Scadenza") {
                    Toggle("Solo entro un limite", isOn: $dueWithinEnabled.animation(.dsQuick))
                    if dueWithinEnabled {
                        Stepper("Entro \(dueWithinDays) giorni", value: $dueWithinDays, in: 0...60)
                    }
                    Toggle("Includi completate", isOn: $includeDone)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(savedView == nil ? "Nuova lista" : "Modifica lista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(width: 420, height: 520)
        #endif
    }

    /// Chip multi-selezione tinted (E3): tap per accendere/spegnere.
    private func chipToggles<T: Hashable>(
        _ items: [T], selection: Binding<Set<T>>,
        info: @escaping (T) -> (label: String, tint: Color)
    ) -> some View {
        FlowChips(items: items, selection: selection, info: info)
    }

    private func load() {
        guard !didLoad, let savedView else { return }
        didLoad = true
        name = savedView.name
        let filters = savedView.filters
        statuses = Set(filters.statuses)
        priorities = Set(filters.priorities)
        tagIDs = Set(filters.tagIDs)
        dueWithinEnabled = filters.dueWithinDays != nil
        dueWithinDays = filters.dueWithinDays ?? 7
        includeDone = filters.includeDone
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var filters = SavedViewFilters()
        filters.statuses = Array(statuses)
        filters.priorities = Array(priorities)
        filters.tagIDs = Array(tagIDs)
        filters.dueWithinDays = dueWithinEnabled ? dueWithinDays : nil
        filters.includeDone = includeDone

        do {
            if let savedView {
                savedView.name = trimmed
                savedView.filters = filters
                savedView.updatedAt = .now
            } else {
                let (workspace, _) = try SeedService.ensureSeed(in: modelContext)
                let scopeRaw = UserDefaults.standard.string(forKey: WorkspaceScope.storageKey) ?? "all"
                let workspaceID = UUID(uuidString: scopeRaw) ?? workspace.id
                let created = SavedView(
                    workspaceID: workspaceID, name: trimmed,
                    viewType: .list, filters: filters
                )
                modelContext.insert(created)
            }
            try modelContext.save()
            dismiss()
        } catch {
            reportFailure("Smart list save failed: \(error)")
        }
    }
}

/// Chips che vanno a capo da sole, multi-selezione.
private struct FlowChips<T: Hashable>: View {
    let items: [T]
    @Binding var selection: Set<T>
    let info: (T) -> (label: String, tint: Color)

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.s)],
                  alignment: .leading, spacing: DS.s) {
            ForEach(items, id: \.self) { item in
                let (label, tint) = info(item)
                let isOn = selection.contains(item)
                Button {
                    withAnimation(.dsQuick) {
                        if isOn { selection.remove(item) } else { selection.insert(item) }
                    }
                } label: {
                    Text(label)
                        .font(.dsCaption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, DS.s)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(tint.opacity(isOn ? 0.85 : 0.12), in: Capsule())
                        .foregroundStyle(isOn ? .white : tint)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    SmartListEditorView()
        .modelContainer(PreviewSampleData.make().container)
}
