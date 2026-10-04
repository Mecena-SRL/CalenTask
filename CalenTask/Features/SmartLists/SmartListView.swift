import SwiftUI
import SwiftData

// MARK: - Matcher dei filtri (S4/D62)

extension SavedViewFilters {
    /// Tutti i criteri in AND; array vuoti = nessun vincolo.
    func matches(_ task: TodoTask, now: Date = .now) -> Bool {
        matcher(now: now)(task)
    }

    /// #11 — Il filtro pronto per molte attività: il limite della scadenza
    /// si calcola una volta, non una per attività.
    func matcher(now: Date = .now) -> (TodoTask) -> Bool {
        let dueLimit = dueWithinDays.flatMap {
            Calendar.app.date(byAdding: .day, value: $0 + 1, to: Calendar.app.startOfDay(for: now))
        }
        return { task in
            guard task.deletedAt == nil, !task.isTemplate, !task.isPhase else { return false }
            if !includeDone && task.isDone { return false }
            if !statuses.isEmpty && !statuses.contains(task.status) { return false }
            if !priorities.isEmpty && !priorities.contains(task.priority) { return false }
            if !kinds.isEmpty && !kinds.contains(task.kind) { return false }
            if !tagIDs.isEmpty {
                let taskTagIDs = Set(task.tags.filter { $0.deletedAt == nil }.map(\.id))
                if !tagIDs.contains(where: taskTagIDs.contains) { return false }
            }
            if dueWithinDays != nil {
                guard let dueAt = task.dueAt, let dueLimit else { return false }
                if dueAt >= dueLimit { return false }
            }
            return true
        }
    }

    /// #11 — Badge delle liste smart in un passaggio: le attività divise per
    /// spazio una volta sola, ogni lista scorre solo quelle del suo spazio.
    static func counts(for lists: [SavedView], in tasks: [TodoTask],
                       now: Date = .now) -> [UUID: Int] {
        guard !lists.isEmpty else { return [:] }
        let byWorkspace = Dictionary(grouping: tasks, by: \.workspaceID)
        var counts: [UUID: Int] = [:]
        for list in lists {
            let matches = list.filters.matcher(now: now)
            counts[list.id] = byWorkspace[list.workspaceID]?.count(where: matches) ?? 0
        }
        return counts
    }
}

// MARK: - Lista smart (S4/D62)

/// Una smart list salvata: i filtri di SavedView applicati dal vivo.
/// Destinazione di navigazione (D70): lo stack lo fornisce l'host
/// (detail su Mac/iPad, push dentro Sfoglia su iPhone).
struct SmartListView: View {
    @Bindable var savedView: SavedView

    @State private var isEditing = false

    var body: some View {
        // #5 — dallo store solo lo spazio della lista (e solo le aperte se
        // la lista non include le completate); il resto dei filtri in memoria.
        SmartListTasks(
            filters: savedView.filters,
            workspaceID: savedView.workspaceID
        )
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

private struct SmartListTasks: View {
    let filters: SavedViewFilters
    @Query private var candidates: [TodoTask]

    init(filters: SavedViewFilters, workspaceID: UUID) {
        self.filters = filters
        if filters.includeDone {
            _candidates = Query(filter: #Predicate<TodoTask> {
                $0.workspaceID == workspaceID && $0.deletedAt == nil && !$0.isTemplate
            })
        } else {
            _candidates = Query(filter: TodoTask.openPredicate(workspaceID: workspaceID))
        }
    }

    private var tasks: [TodoTask] {
        candidates
            .filter(filters.matcher())
            .sorted {
                ($0.dueAt ?? .distantFuture, $1.priorityRaw)
                    < ($1.dueAt ?? .distantFuture, $0.priorityRaw)
            }
    }

    var body: some View {
        let tasks = tasks
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
