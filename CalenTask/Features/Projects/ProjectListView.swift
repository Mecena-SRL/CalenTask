import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showsNewProject = false
    /// E7 — apertura "a foglio": la card si espande nel dettaglio (iOS).
    @Namespace private var zoomNamespace

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    private var projects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    // F32 — i progetti raggruppati per vita: attivi, lungo termine, chiusi.
    private var activeProjects: [Project] {
        projects.filter { $0.status == .active }
    }

    private var pausedProjects: [Project] {
        projects.filter { $0.status == .paused }
    }

    private var closedProjects: [Project] {
        projects.filter { $0.status == .completed || $0.status == .archived }
    }

    @AppStorage("projectsShowsClosed") private var showsClosed = false

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    DSEmptyState(
                        icon: "folder",
                        title: "Nessun progetto",
                        subtitle: "Parti da un template cinema o business, o da un foglio bianco.",
                        actionTitle: "Nuovo progetto",
                        action: { showsNewProject = true }
                    )
                } else {
                    // F32 — una dashboard, non un elenco: numeri in testa,
                    // griglia adattiva (1 colonna su iPhone, 2-3 su un 32").
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.xl) {
                            statTiles

                            if !activeProjects.isEmpty {
                                projectsSection("Attivi", projects: activeProjects,
                                                showsNewTile: true)
                            }
                            if !pausedProjects.isEmpty {
                                projectsSection("Lungo termine · in pausa",
                                                projects: pausedProjects)
                            }
                            if !closedProjects.isEmpty {
                                closedSection
                            }
                        }
                        .padding(DS.l)
                    }
                    .background(DSColor.surfaceSecondary)
                }
            }
            .navigationTitle("Progetti")
            .toolbar {
                // Solo iPhone: su iPad l'item .navigation copriva il toggle
                // della sidebar; lo scope vive già nella sua testata (D44).
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .navigation) {
                        WorkspaceScopePicker()
                    }
                }
                #endif
                // G3 — su macOS gli item di toolbar della radice restano
                // visibili anche nelle viste pushate (doppio "+"): il
                // "Nuovo progetto" su Mac vive come tile nella griglia.
                #if os(iOS)
                ToolbarItem {
                    Button {
                        showsNewProject = true
                    } label: {
                        Label("Nuovo progetto", systemImage: "plus")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showsNewProject) {
                NewProjectSheet()
            }
        }
    }

    // MARK: Numeri in testa (F32)

    private var statTiles: some View {
        let allLive = projects.flatMap { project in
            project.tasks.filter { $0.deletedAt == nil && !$0.isPhase && !$0.isTemplate }
        }
        let open = allLive.filter { !$0.isDone }
        let overdue = open.filter(\.isOverdue)
        return HStack(spacing: DS.m) {
            StatTile(title: "Attivi", count: activeProjects.count,
                     icon: "folder.fill", tint: AppSection.projects.tint)
            StatTile(title: "Attività aperte", count: open.count, icon: "circle") {}
            StatTile(title: "In ritardo", count: overdue.count,
                     icon: "exclamationmark.circle", tint: DSColor.overdue)
            StatTile(title: "Archiviati", count: closedProjects.count,
                     icon: "archivebox", tint: .secondary)
        }
    }

    // MARK: Sezioni (F32)

    private func projectsSection(
        _ title: String, projects: [Project], showsNewTile: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: title, count: projects.count)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 380, maximum: 640),
                                   spacing: DS.m, alignment: .top)],
                alignment: .leading,
                spacing: DS.m
            ) {
                ForEach(projects, id: \.id) { project in
                    projectLink(project)
                }
                #if os(macOS)
                if showsNewTile {
                    newProjectTile
                }
                #endif
            }
        }
    }

    #if os(macOS)
    /// G3 — la creazione vive nella griglia, non in toolbar.
    private var newProjectTile: some View {
        Button {
            showsNewProject = true
        } label: {
            HStack(spacing: DS.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Nuovo progetto")
                    .font(.dsMeta.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(DS.l)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.medium)
                    .strokeBorder(DSColor.hairlineStrong,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DS.Radius.medium)
    }
    #endif

    private func projectLink(_ project: Project) -> some View {
        NavigationLink {
            ProjectDetailView(project: project)
                #if os(iOS)
                .navigationTransition(.zoom(sourceID: project.id, in: zoomNamespace))
                #endif
        } label: {
            ProjectCard(project: project) { viewType in
                // Jump straight into the chosen view (D26).
                UserDefaults.standard.set(viewType.rawValue, forKey: "lastProjectViewType")
                router.open(projectID: project.id)
            }
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .matchedTransitionSource(id: project.id, in: zoomNamespace)
        #endif
        .contextMenu {
            ProjectMenuContent(project: project) { viewType in
                UserDefaults.standard.set(viewType.rawValue, forKey: "lastProjectViewType")
                router.open(projectID: project.id)
            }
        }
    }

    /// Archiviati e completati: ripiegati, righe leggere (F32).
    private var closedSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Button {
                withAnimation(.dsQuick) { showsClosed.toggle() }
            } label: {
                HStack(spacing: DS.s) {
                    DSSectionHeader(title: "Archiviati", count: closedProjects.count)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsClosed ? 90 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsClosed {
                VStack(spacing: 0) {
                    ForEach(closedProjects, id: \.id) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            HStack(spacing: DS.m) {
                                Circle()
                                    .fill(Color(hex: project.colorHex).opacity(0.5))
                                    .frame(width: 10, height: 10)
                                Text(project.name)
                                    .font(.dsMeta)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(project.status.label)
                                    .font(.dsCaption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, DS.m)
                            .padding(.vertical, DS.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ProjectMenuContent(project: project)
                        }
                        if project.id != closedProjects.last?.id {
                            Divider().padding(.leading, DS.xl)
                        }
                    }
                }
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            }
        }
    }
}

/// Menu contestuale dei progetti (D46): apri nelle viste, stato, elimina.
struct ProjectMenuContent: View {
    @Bindable var project: Project
    var onOpenView: (ProjectViewType) -> Void = { _ in }

    var body: some View {
        // D75 — il preferito a un tap, ovunque il progetto appaia.
        Button {
            withAnimation(.dsQuick) {
                project.isFavorite.toggle()
                project.updatedAt = .now
            }
        } label: {
            Label(project.isFavorite ? "Rimuovi dai Preferiti" : "Aggiungi ai Preferiti",
                  systemImage: project.isFavorite ? "star.slash" : "star")
        }
        Section("Apri in") {
            ForEach(ProjectViewType.allCases) { type in
                Button {
                    onOpenView(type)
                } label: {
                    Label(type.label, systemImage: type.systemImage)
                }
            }
        }
        Menu {
            Picker("Stato", selection: Binding(
                get: { project.status },
                set: { project.status = $0; project.updatedAt = .now }
            )) {
                ForEach(ProjectStatus.allCases, id: \.self) { status in
                    Text(status.label).tag(status)
                }
            }
        } label: {
            Label("Stato progetto", systemImage: "circle.lefthalf.filled")
        }
        Divider()
        Button(role: .destructive) {
            withAnimation { project.deletedAt = .now; project.updatedAt = .now }
        } label: {
            Label("Elimina progetto", systemImage: "trash")
        }
    }
}

private struct ProjectCard: View {
    let project: Project
    /// Quick jump into a specific view (Elenco/Bacheca/Kanban/Gantt — D26).
    var onOpenView: (ProjectViewType) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.s) {
                Circle()
                    .fill(Color(hex: project.colorHex))
                    .frame(width: 10, height: 10)
                Text(project.name)
                    .font(.dsRowTitle)
                    .lineLimit(1)
                // S6/D64 — Smart Status: la salute si vede a colpo d'occhio.
                let status = project.smartStatus
                if status != .onTrack {
                    Text(status.label)
                        .font(.dsCaption.weight(.medium))
                        .padding(.horizontal, DS.s)
                        .padding(.vertical, 2)
                        .background(status.color.opacity(0.14), in: Capsule())
                        .foregroundStyle(status.color)
                }
                Spacer()
                HStack(spacing: DS.xs) {
                    ForEach(ProjectViewType.allCases) { type in
                        Button {
                            onOpenView(type)
                        } label: {
                            Image(systemName: type.systemImage)
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    DSColor.surface.opacity(0.8),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(type.label)
                        .accessibilityLabel("Apri \(project.name) in vista \(type.label)")
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }

            let open = openTasks
            HStack(spacing: DS.m) {
                if totalTasks > 0 {
                    ProgressView(value: progress)
                        .tint(Color(hex: project.colorHex))
                        .frame(maxWidth: 160)
                    Text("\(doneTasks)/\(totalTasks)")
                        .font(.dsNumeric)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nessuna attività")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let nextDue = open.compactMap(\.dueAt).min() {
                    Label(nextDue.dsRelativeLabel, systemImage: "flag")
                        .font(.dsCaption)
                        .foregroundStyle(nextDue < .now.startOfDay ? DSColor.overdue : .secondary)
                }
            }
        }
        .padding(DS.l)
        .dsSurface(.card)
    }

    private var liveTasks: [TodoTask] { project.tasks.filter { $0.deletedAt == nil } }
    private var totalTasks: Int { liveTasks.count }
    private var doneTasks: Int { liveTasks.filter(\.isDone).count }
    private var openTasks: [TodoTask] { liveTasks.filter { !$0.isDone } }
    private var progress: Double {
        totalTasks > 0 ? Double(doneTasks) / Double(totalTasks) : 0
    }
}

#Preview {
    ProjectListView()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
