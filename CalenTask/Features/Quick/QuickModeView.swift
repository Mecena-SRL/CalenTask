import SwiftUI
import SwiftData

/// Modalità rapida (D11/D20) — "alla Google Tasks": one line to capture, a
/// clean readable list, cards that expand inline to go deeper.
/// Scope: ALL workspaces by default; filter per workspace, created-by-me or
/// assigned-to-me. Sorting and filtering live in the toolbar.
struct QuickModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil },
           sort: \Workspace.createdAt)
    private var workspaces: [Workspace]

    // F5 — il menu progetto dei parametri rapidi.
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    private var captureProjects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    @Query(filter: TodoTask.openPredicate, sort: \TodoTask.createdAt, order: .reverse)
    private var openTasks: [TodoTask]

    /// F12 — le completate vivono in coda, su richiesta.
    @Query(filter: #Predicate<TodoTask> {
        $0.deletedAt == nil && !$0.isTemplate && $0.completedAt != nil
    }, sort: \TodoTask.completedAt, order: .reverse)
    private var doneTasks: [TodoTask]

    private var recentlyDone: [TodoTask] {
        let cutoff = Calendar.app.date(byAdding: .day, value: -7, to: .now) ?? .now
        var base = doneTasks.filter { ($0.completedAt ?? .distantPast) >= cutoff }
        base = WorkspaceScope.filter(base, raw: scopeRaw, id: \.workspaceID)
        return Array(base.prefix(20))
    }

    // Scope spazio: GLOBALE, condiviso con tutta l'app (D44).
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    // Filtro persona locale alla Rapida: "none" | "mine-created" | "mine-assigned"
    @AppStorage("quickPersonFilter") private var personFilterRaw = "none"
    // Sort: "smart" | "priority" | "due" | "created" | "title"
    @AppStorage("quickSort") private var sortRaw = "smart"
    // Filters
    @AppStorage("quickFilterStatus") private var filterStatusRaw = "all"
    @AppStorage("quickFilterDueOnly") private var filterDueOnly = false
    @AppStorage("quickFilterClaimable") private var filterClaimable = false
    /// F12 — standard delle altre app: rivedere le completate recenti.
    @AppStorage("quickShowsDone") private var showsRecentlyDone = false

    // Configurable fields on quick cards (D11).
    @AppStorage("quickShowsDue") private var showsDue = true
    @AppStorage("quickShowsPhase") private var showsPhase = true
    @AppStorage("quickShowsPriority") private var showsPriority = false
    @AppStorage("quickShowsNotes") private var showsNotes = false

    @State private var newTitle = ""
    @State private var expandedTaskID: UUID?
    @State private var showsTagManager = false
    @State private var showsComposer = false
    @FocusState private var isCaptureFocused: Bool
    @State private var captureProject: Project?
    @State private var captureSuppressDate = false
    @State private var captureSuppressPriority = false
    // F5 — i parametri rapidi espliciti, a un tap dal campo.
    @State private var showsQuickParams = false
    @State private var captureDue: Date?
    @State private var capturePriority: TaskPriority = .normal

    // Smart list (S4/D62): da Rapida si aprono e si creano.
    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil && $0.projectID == nil },
           sort: \SavedView.createdAt)
    private var allSavedViews: [SavedView]
    @State private var isCreatingSmartList = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                captureBar
                list
            }
            .background(DSColor.surfaceSecondary)
            .navigationTitle("Rapida")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Lo scope in toolbar SOLO dove non c'è la sidebar (iPhone):
                // su Mac/iPad vive nella testata della sidebar (D44) — e su
                // iPad l'item .navigation copriva il toggle della sidebar.
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .navigation) {
                        WorkspaceScopePicker()
                    }
                }
                #endif
                // F19 — gli aggiornamenti anche dalla prima pagina.
                ToolbarItem {
                    NotificationsBellButton()
                }
                ToolbarItem {
                    smartListsMenu
                }
                ToolbarItem {
                    sortFilterMenu
                }
                ToolbarItem {
                    fieldsMenu
                }
            }
            .sheet(isPresented: $showsTagManager) {
                TagManagerView()
            }
            .sheet(isPresented: $showsComposer, onDismiss: { isCaptureFocused = true }) {
                TaskComposerView(initialTitle: newTitle.trimmingCharacters(in: .whitespaces))
                    .onAppear { newTitle = "" }
            }
            .sheet(isPresented: $isCreatingSmartList) {
                SmartListEditorView()
            }
        }
    }

    /// Le liste smart a un tap (D62): si aprono come destinazioni (D70).
    /// F11 — il menu spiega COSA sono: filtri salvati che si riempiono da soli.
    private var smartListsMenu: some View {
        Menu {
            Section("Liste smart — si riempiono da sole con i filtri che scegli") {
                ForEach(allSavedViews, id: \.id) { list in
                    Button {
                        router.open(smartListID: list.id)
                    } label: {
                        Label(list.name, systemImage: "bookmark.fill")
                    }
                }
            }
            Divider()
            Button {
                isCreatingSmartList = true
            } label: {
                Label("Nuova lista smart…", systemImage: "plus")
            }
        } label: {
            Label("Liste", systemImage: "bookmark")
        }
        .help("Liste smart: filtri salvati (stato, priorità, etichette) sempre aggiornati")
    }

    // MARK: Capture

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.m) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                TextField("Aggiungi a \(captureTargetName)…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.dsRowTitle)
                    .focused($isCaptureFocused)
                    .onSubmit(capture)
                // F5 — i due tasti chiesti: parametri rapidi e modifica a fondo.
                Button {
                    withAnimation(.dsQuick) { showsQuickParams.toggle() }
                } label: {
                    Image(systemName: showsQuickParams
                          ? "slider.horizontal.3" : "slider.horizontal.3")
                        .foregroundStyle(showsQuickParams ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Parametri rapidi: scadenza, priorità, progetto")
                .accessibilityLabel("Mostra parametri rapidi")
                Button {
                    showsComposer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Apri l'attività nel composer completo")
                .accessibilityLabel("Apri il composer completo")
            }
            // D60: autocomplete live e chip annullabili anche qui, in prima pagina.
            CaptureAssistView(
                text: $newTitle,
                selectedProject: $captureProject,
                suppressDate: $captureSuppressDate,
                suppressPriority: $captureSuppressPriority
            )

            // F5 — la riga dei parametri rapidi.
            if showsQuickParams {
                HStack(spacing: DS.m) {
                    DateChipPicker(label: "Scadenza", date: $captureDue)
                    Menu {
                        Picker("Priorità", selection: $capturePriority) {
                            ForEach(TaskPriority.allCases.reversed()) { level in
                                Label(level.label, systemImage: "flag.fill").tag(level)
                            }
                        }
                    } label: {
                        Label(capturePriority.label, systemImage: "flag")
                            .font(.dsCaption)
                            .foregroundStyle(capturePriority == .normal
                                ? Color.secondary : DSColor.priority(capturePriority))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Menu {
                        Picker("Progetto", selection: $captureProject) {
                            Text("Inbox (nessuno)").tag(nil as Project?)
                            ForEach(captureProjects, id: \.id) { project in
                                Text(project.name).tag(project as Project?)
                            }
                        }
                    } label: {
                        Label(captureProject?.name ?? "Progetto",
                              systemImage: "folder")
                            .font(.dsCaption)
                            .foregroundStyle(captureProject.map {
                                Color(hex: $0.colorHex)
                            } ?? .secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DS.l)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(DSColor.hairline)
        }
        // Proporzioni (D76): la barra resta una "command bar" leggibile
        // anche su un 32" — larghezza da testo, centrata.
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .padding([.horizontal, .top], DS.l)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let tasks = visibleTasks
        if tasks.isEmpty {
            DSEmptyState(
                icon: "bolt",
                title: "Tutto fatto",
                subtitle: "Scrivi qui sopra e premi Invio: pensa, cattura, via."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                // F4 — una sola colonna centrale: la Rapida è una lista,
                // la semplicità è il punto (supera D76).
                LazyVStack(spacing: DS.s) {
                    ForEach(tasks, id: \.id) { task in
                        QuickTaskCard(
                            task: task,
                            isExpanded: expandedTaskID == task.id,
                            showsDue: showsDue,
                            showsPhase: showsPhase,
                            showsPriority: showsPriority,
                            showsNotes: showsNotes,
                            showsWorkspace: scopeRaw == "all" && workspaces.count > 1,
                            workspaces: workspaces,
                            onTap: {
                                // Collapsing = done editing inline: re-derive #tags.
                                if expandedTaskID == task.id {
                                    TagService.syncTags(for: task, in: modelContext)
                                }
                                withAnimation(.dsQuick) {
                                    expandedTaskID = expandedTaskID == task.id ? nil : task.id
                                }
                            }
                        )
                        .taskContextMenu(task)
                    }

                    // F12 — come nelle altre app: le completate si possono
                    // rivedere (ultimi 7 giorni), spuntare di nuovo, ripescare.
                    if showsRecentlyDone, !recentlyDone.isEmpty {
                        Text("Completate di recente")
                            .font(.dsCaption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DS.m)
                        ForEach(recentlyDone, id: \.id) { task in
                            QuickTaskCard(
                                task: task,
                                isExpanded: false,
                                showsDue: showsDue,
                                showsPhase: showsPhase,
                                showsPriority: showsPriority,
                                showsNotes: showsNotes,
                                showsWorkspace: false,
                                workspaces: workspaces,
                                onTap: {}
                            )
                            .opacity(0.6)
                            .taskContextMenu(task)
                        }
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(DS.l)
            }
        }
    }

    // MARK: Scope (D20)

    private var currentUserID: UUID? {
        UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
    }

    private var scopedTasks: [TodoTask] {
        var base = openTasks.filter { $0.parentTask == nil || $0.parentTask?.isPhase == true }
        base = WorkspaceScope.filter(base, raw: scopeRaw, id: \.workspaceID)
        switch personFilterRaw {
        case "mine-created":
            return base.filter { $0.createdByID == currentUserID }
        case "mine-assigned":
            return base.filter { $0.assigneeID == currentUserID }
        default:
            return base
        }
    }

    private var visibleTasks: [TodoTask] {
        var tasks = scopedTasks
        if let status = TaskStatus(rawValue: filterStatusRaw) {
            tasks = tasks.filter { $0.status == status }
        }
        if filterDueOnly { tasks = tasks.filter { $0.dueAt != nil } }
        if filterClaimable { tasks = tasks.filter(\.isClaimable) }
        return sorted(tasks)
    }

    private func sorted(_ tasks: [TodoTask]) -> [TodoTask] {
        switch sortRaw {
        case "priority":
            return tasks.sorted {
                ($0.priorityRaw, $1.createdAt.timeIntervalSince1970)
                    > ($1.priorityRaw, $0.createdAt.timeIntervalSince1970)
            }
        case "due":
            return tasks.sorted {
                ($0.dueAt ?? .distantFuture, $0.createdAt) < ($1.dueAt ?? .distantFuture, $1.createdAt)
            }
        case "created":
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case "title":
            return tasks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        default:  // smart: dated first by urgency, then newest captures
            return tasks.sorted { lhs, rhs in
                switch (lhs.dueAt, rhs.dueAt) {
                case let (l?, r?): l < r
                case (.some, nil): true
                case (nil, .some): false
                default: lhs.createdAt > rhs.createdAt
                }
            }
        }
    }


    // MARK: Sort & filter (D20)

    private var sortFilterMenu: some View {
        Menu {
            Section("Ordina per") {
                Picker("Ordina", selection: $sortRaw) {
                    Label("Intelligente", systemImage: "wand.and.stars").tag("smart")
                    Label("Priorità", systemImage: "flag").tag("priority")
                    Label("Scadenza", systemImage: "calendar").tag("due")
                    Label("Più recenti", systemImage: "clock").tag("created")
                    Label("Titolo", systemImage: "textformat").tag("title")
                }
            }
            Section("Filtra") {
                Picker("Stato", selection: $filterStatusRaw) {
                    Text("Tutti gli stati").tag("all")
                    ForEach(TaskStatus.allCases.filter { $0 != .done }) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }
                Toggle("Solo con scadenza", isOn: $filterDueOnly)
                Toggle("Prendibili dal team", isOn: $filterClaimable)
                Toggle("Completate di recente", isOn: $showsRecentlyDone)
                Picker("Persona", selection: $personFilterRaw) {
                    Text("Di tutti").tag("none")
                    Text("Creati da me").tag("mine-created")
                    Text("Assegnati a me").tag("mine-assigned")
                }
            }
            if hasActiveFilters {
                Divider()
                Button("Azzera filtri") {
                    filterStatusRaw = "all"
                    filterDueOnly = false
                    filterClaimable = false
                    personFilterRaw = "none"
                }
            }
        } label: {
            Label("Ordina e filtra", systemImage: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var hasActiveFilters: Bool {
        filterStatusRaw != "all" || filterDueOnly || filterClaimable
            || personFilterRaw != "none"
    }

    private var fieldsMenu: some View {
        Menu {
            Section("Campi visibili") {
                Toggle("Scadenza", isOn: $showsDue)
                Toggle("Fase e colore", isOn: $showsPhase)
                Toggle("Priorità", isOn: $showsPriority)
                Toggle("Anteprima note", isOn: $showsNotes)
            }
            Divider()
            Button {
                showsTagManager = true
            } label: {
                Label("Etichette…", systemImage: "number")
            }
            #if os(macOS)
            SettingsLink {
                Label("Impostazioni…", systemImage: "gearshape")
            }
            #else
            Button {
                router.isSettingsOpen = true
            } label: {
                Label("Impostazioni…", systemImage: "gearshape")
            }
            #endif
        } label: {
            Label("Campi", systemImage: "slider.horizontal.3")
        }
    }

    // MARK: Capture target

    /// New captures land in the scoped workspace, or Personale by default (D11).
    private var captureWorkspace: Workspace? {
        if scopeRaw != "all", let scoped = workspaces.first(where: { $0.id.uuidString == scopeRaw }) {
            return scoped
        }
        return workspaces.first(where: \.isPersonal) ?? workspaces.first
    }

    private var captureTargetName: String {
        captureWorkspace?.name ?? "Personale"
    }

    private func capture() {
        let text = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let (_, me) = try SeedService.ensureSeed(in: modelContext)
            guard let workspace = captureWorkspace else { return }
            let task = TodoTask(
                workspaceID: workspace.id,
                title: text,
                createdByID: me.id
            )
            modelContext.insert(task)
            // D60: titolo ripulito, !priorità, /progetto, date nel testo, #tag.
            CaptureApplier.apply(
                text: text, to: task,
                selectedProject: captureProject,
                suppressDate: captureSuppressDate,
                suppressPriority: captureSuppressPriority,
                in: modelContext
            )
            // F5 — i parametri espliciti vincono sul testo interpretato.
            if let captureDue { task.dueAt = captureDue }
            if capturePriority != .normal { task.priority = capturePriority }
            try modelContext.save()
            NotificationService.shared.sync(task: task)
            newTitle = ""
            captureProject = nil
            captureSuppressDate = false
            captureSuppressPriority = false
            captureDue = nil
            capturePriority = .normal
            isCaptureFocused = true
        } catch {
            reportFailure("Quick capture failed: \(error)")
        }
    }
}

// MARK: - Card

/// One quick card: compact line that expands inline for depth — notes, dates,
/// type, claimable, priority, workspace move, full editor (D11/D22).
private struct QuickTaskCard: View {
    @Environment(AppRouter.self) private var router
    @Bindable var task: TodoTask
    let isExpanded: Bool
    let showsDue: Bool
    let showsPhase: Bool
    let showsPriority: Bool
    let showsNotes: Bool
    let showsWorkspace: Bool
    let workspaces: [Workspace]
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactRow
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.medium)
                    .fill(DSColor.surface)
                if let wash = accentColor {
                    // The first #label colors the card (D21).
                    RoundedRectangle(cornerRadius: DS.Radius.medium)
                        .fill(wash.opacity(0.08))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .overlay(alignment: .leading) {
            if let tint = stripeTint {
                // Label color first, phase/project color as fallback (D11/D21).
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.medium,
                    bottomLeadingRadius: DS.Radius.medium
                )
                .fill(tint)
                .frame(width: 4)
            }
        }
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private var compactRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.m) {
            DSCheckToggle(isDone: task.isDone) {
                withAnimation(.dsSoft) { task.toggleDone() }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.s) {
                    if showsPriority {
                        PriorityDot(priority: task.priority)
                    }
                    if task.kind != .task {
                        Image(systemName: task.kind.systemImage)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.title)
                        .font(.dsMeta.weight(.medium))
                        .lineLimit(isExpanded ? nil : 2)
                }
                metadataLine
            }
            Spacer(minLength: 0)
            if task.isClaimable {
                Image(systemName: "hand.raised")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
                    .help("Prendibile dal team")
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(DS.m)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var metadataLine: some View {
        let pieces = metadataPieces
        if !pieces.isEmpty {
            HStack(spacing: DS.s) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Label(piece.text, systemImage: piece.icon)
                        .foregroundStyle(piece.tint)
                }
            }
            .font(.dsCaption)
        }
    }

    private var metadataPieces: [(text: String, icon: String, tint: Color)] {
        var result: [(String, String, Color)] = []
        if showsDue, let dueAt = task.dueAt {
            result.append((
                dueAt.dsRelativeLabel, "flag",
                task.isOverdue ? DSColor.overdue : .secondary
            ))
        }
        if showsPhase, let phase = task.phaseAncestor {
            result.append((phase.title, "square.stack.3d.up", phaseTint ?? .secondary))
        } else if showsPhase, let project = task.project {
            result.append((project.name, "folder", Color(hex: project.colorHex)))
        }
        if showsWorkspace,
           let workspace = workspaces.first(where: { $0.id == task.workspaceID }) {
            result.append((
                workspace.name,
                workspace.isPersonal ? "person" : "building.2",
                Color(hex: workspace.colorHex)
            ))
        }
        if showsNotes, !task.notes.isEmpty {
            result.append((task.notes.components(separatedBy: .newlines).first ?? "",
                           "note.text", .secondary))
        }
        return result
    }

    private var phaseTint: Color? {
        task.project.map { Color(hex: $0.colorHex) }
    }

    /// First #label color (D21) — beats the project tint when present.
    private var accentColor: Color? {
        task.accentTagColorHex.map { Color(hex: $0) }
    }

    private var stripeTint: Color? {
        accentColor ?? (showsPhase ? phaseTint : nil)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            Divider()

            DateChipPicker(label: "Scadenza", date: Binding(
                get: { task.dueAt },
                set: { task.setDue($0) }
            ))

            TextField("Note… (#etichetta per colorare)", text: Binding(
                get: { task.notes },
                set: { task.notes = $0; task.updatedAt = .now }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.dsCaption)
            .lineLimit(1...4)

            // Censimento veloce (D22): tipo, priorità, prendibile dal team.
            HStack(spacing: DS.m) {
                Menu {
                    Picker("Tipo", selection: kindBinding) {
                        ForEach([TaskKind.task, .reminder, .event]) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                } label: {
                    Label(task.kind.label, systemImage: task.kind.systemImage)
                        .font(.dsCaption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    Picker("Priorità", selection: priorityBinding) {
                        ForEach(TaskPriority.allCases.reversed()) { level in
                            Label(level.label, systemImage: "flag.fill").tag(level)
                        }
                    }
                } label: {
                    Label(task.priority.label, systemImage: "flag")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.priority(task.priority))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Toggle(isOn: Binding(
                    get: { task.isClaimable },
                    set: { task.isClaimable = $0; task.touch() }
                )) {
                    Label("Team", systemImage: "hand.raised")
                        .font(.dsCaption)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(task.isClaimable ? Color.accentColor : Color.secondary)
                .help("Prendibile dal team: visibile nella lista condivisa")
            }

            HStack {
                // "È personale o no?" — move between workspaces in one tap (D11).
                Menu {
                    Picker("Spazio", selection: workspaceBinding) {
                        ForEach(workspaces, id: \.id) { workspace in
                            Label(
                                workspace.name,
                                systemImage: workspace.isPersonal ? "person" : "building.2"
                            )
                            .tag(workspace.id)
                        }
                    }
                } label: {
                    Label(workspaceName, systemImage: "arrow.left.arrow.right")
                        .font(.dsCaption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                // F14 — su Mac i dettagli aprono l'inspector a destra;
                // su iPhone restano un push nello stack.
                #if os(macOS)
                Button {
                    router.inspect(taskID: task.id)
                } label: {
                    Label("Dettagli", systemImage: "sidebar.trailing")
                        .font(.dsCaption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                #else
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    Label("Dettagli", systemImage: "arrow.up.right.square")
                        .font(.dsCaption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                #endif
            }
        }
        .padding([.horizontal, .bottom], DS.m)
    }

    private var kindBinding: Binding<TaskKind> {
        Binding(get: { task.kind }, set: { task.kind = $0; task.touch() })
    }

    private var priorityBinding: Binding<TaskPriority> {
        Binding(get: { task.priority }, set: { task.priority = $0; task.touch() })
    }

    private var workspaceName: String {
        workspaces.first { $0.id == task.workspaceID }?.name ?? "Spazio"
    }

    private var workspaceBinding: Binding<UUID> {
        Binding(
            get: { task.workspaceID },
            set: { newID in
                task.workspaceID = newID
                // Project/phase belong to the old workspace: detach.
                if task.project != nil, task.project?.workspaceID != newID {
                    task.project = nil
                    task.parentTask = nil
                }
                task.touch()
            }
        )
    }
}

#Preview {
    QuickModeView()
        .modelContainer(PreviewSampleData.make().container)
}
