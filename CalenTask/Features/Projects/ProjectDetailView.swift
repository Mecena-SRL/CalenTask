import SwiftUI
import SwiftData

/// Project detail with the D8 view switcher:
/// Elenco · Bacheca (per fase) · Kanban (per stato) · Gantt.
struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var showsPlanner = false
    @State private var showsPipeline = false
    @State private var showsAutomations = false
    @State private var showsFields = false
    @State private var showsCrew = false

    /// Last-used view follows the user across projects.
    @AppStorage("lastProjectViewType") private var viewTypeRaw = ProjectViewType.list.rawValue
    /// F34 — quali viste tenere nella barra (scelta dell'utente, globale).
    @AppStorage("projectHiddenViews") private var hiddenViewsRaw = ""

    private var viewType: ProjectViewType {
        ProjectViewType(rawValue: viewTypeRaw) ?? .list
    }

    private var hiddenViews: Set<String> {
        Set(hiddenViewsRaw.split(separator: ",").map(String.init))
    }

    /// F39 — Scene compare solo se attivata (o se il progetto ha già
    /// giornate di ripresa: i dati esistenti non spariscono).
    private var productionAvailable: Bool {
        project.productionEnabled || project.tasks.contains {
            $0.kindRaw == TaskKind.shootDay.rawValue && $0.deletedAt == nil
        }
    }

    private var visibleViews: [ProjectViewType] {
        ProjectViewType.allCases.filter { type in
            if type == .stripboard { return productionAvailable }
            return !hiddenViews.contains(type.rawValue)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The view switcher lives IN the page, always visible (D26).
            Picker("Vista", selection: $viewTypeRaw.animation(.dsQuick)) {
                ForEach(visibleViews) { type in
                    Label(type.label, systemImage: type.systemImage)
                        .tag(type.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s)
            .onAppear {
                // La vista salvata potrebbe essere nascosta: si ripiega.
                if !visibleViews.contains(viewType) {
                    viewTypeRaw = (visibleViews.first ?? .list).rawValue
                }
            }

            switch viewType {
            case .summary:
                ProjectSummaryView(project: project)
            case .list:
                ProjectListContentView(project: project)
            case .board:
                ProjectBoardView(project: project)
            case .kanban:
                ProjectKanbanView(project: project)
            case .gantt:
                ProjectGanttView(project: project)
            case .stripboard:
                ProjectStripboardView(project: project)
            }
        }
        .navigationTitle(project.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // D75 — la stella del preferito, sempre a portata.
            ToolbarItem {
                Button {
                    withAnimation(.dsQuick) {
                        project.isFavorite.toggle()
                        project.updatedAt = .now
                    }
                } label: {
                    Label(project.isFavorite ? "Rimuovi dai Preferiti"
                                             : "Aggiungi ai Preferiti",
                          systemImage: project.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(project.isFavorite ? .yellow
                                         : Color.secondary)
                }
            }
            // Un solo menu: niente toolbar affollata (eleganza, D26).
            ToolbarItem {
                Menu {
                    Button {
                        showsPipeline = true
                    } label: {
                        Label("Pipeline…", systemImage: "arrow.right.square")
                    }
                    Button {
                        showsAutomations = true
                    } label: {
                        Label("Automazioni…", systemImage: "bolt.badge.automatic")
                    }
                    Button {
                        showsFields = true
                    } label: {
                        Label("Campi…", systemImage: "tablecells")
                    }
                    Button {
                        showsCrew = true
                    } label: {
                        Label("Troupe e risorse…", systemImage: "person.2")
                    }
                    Divider()
                    Button {
                        showsPlanner = true
                    } label: {
                        Label("Pianifica fasi…", systemImage: "text.append")
                    }
                    .disabled(project.phaseTasks.isEmpty)
                    Divider()
                    // F34 — decidere quali viste vedere e quali no.
                    Section("Viste") {
                        ForEach(ProjectViewType.allCases.filter { $0 != .stripboard }) { type in
                            Toggle(isOn: viewVisibilityBinding(type)) {
                                Label(type.label, systemImage: type.systemImage)
                            }
                        }
                        // F39 — la produzione video si accende per progetto.
                        Toggle(isOn: Binding(
                            get: { productionAvailable },
                            set: { enabled in
                                withAnimation(.dsQuick) {
                                    project.productionEnabled = enabled
                                    project.updatedAt = .now
                                    if !enabled, viewType == .stripboard {
                                        viewTypeRaw = ProjectViewType.list.rawValue
                                    }
                                }
                            }
                        )) {
                            Label("Scene (produzione video)", systemImage: "film")
                        }
                    }
                } label: {
                    Label("Strumenti", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showsPlanner) {
            PhasePlannerView(project: project)
        }
        .sheet(isPresented: $showsPipeline) {
            PipelineEditorView(project: project)
        }
        .sheet(isPresented: $showsAutomations) {
            AutomationListView(project: project)
        }
        .sheet(isPresented: $showsFields) {
            CustomFieldsEditorView(project: project)
        }
        .sheet(isPresented: $showsCrew) {
            CrewView()
        }
    }

    /// F34 — toggle di visibilità per una vista (almeno una resta sempre).
    private func viewVisibilityBinding(_ type: ProjectViewType) -> Binding<Bool> {
        Binding(
            get: { !hiddenViews.contains(type.rawValue) },
            set: { visible in
                var hidden = hiddenViews
                if visible {
                    hidden.remove(type.rawValue)
                } else {
                    // Mai nascondere l'ultima vista rimasta.
                    let remaining = ProjectViewType.allCases.filter {
                        $0 != .stripboard && !hidden.contains($0.rawValue)
                    }
                    guard remaining.count > 1 else { return }
                    hidden.insert(type.rawValue)
                }
                withAnimation(.dsQuick) {
                    hiddenViewsRaw = hidden.sorted().joined(separator: ",")
                    if !visible, viewType == type {
                        viewTypeRaw = (visibleViews.first ?? .list).rawValue
                    }
                }
            }
        )
    }
}

/// The classic outline list (default view).
private struct ProjectListContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var newPhaseName = ""
    /// G5 — le fasi si riducono; la scelta vive per sessione.
    @State private var collapsedPhases: Set<UUID> = []

    var body: some View {
        // F35 — una colonna leggibile, non gigante, centrata.
        List {
            ForEach(project.phaseTasks, id: \.id) { phase in
                PhaseSectionView(
                    phase: phase,
                    project: project,
                    isCollapsed: collapsedPhases.contains(phase.id),
                    onToggleCollapse: {
                        withAnimation(.dsQuick) {
                            if collapsedPhases.contains(phase.id) {
                                collapsedPhases.remove(phase.id)
                            } else {
                                collapsedPhases.insert(phase.id)
                            }
                        }
                    }
                )
            }

            let unphased = project.unphasedTasks
            if !unphased.isEmpty {
                Section("Senza fase") {
                    ForEach(unphased, id: \.id) { task in
                        TaskOpenLink(task: task) {
                            TaskRow(task: task, showProject: false) {
                                withAnimation(.dsSoft) { task.toggleDone() }
                            }
                        }
                        .taskContextMenu(task)
                    }
                }
            }

            Section {
                HStack(spacing: DS.m) {
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                    DSPromptField(prompt: "Nuova fase", text: $newPhaseName)
                        .onSubmit(addPhase)
                    if !newPhaseName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Aggiungi", action: addPhase)
                            .buttonStyle(.borderless)
                            .font(.dsCaption)
                    }
                }
            }

            // Documenti del progetto: cartelle, contratti, link Drive (D33).
            AttachmentsSection(
                workspaceID: project.workspaceID,
                projectID: project.id,
                title: "Documenti del progetto"
            )
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .background(DSColor.surfaceSecondary)
    }

    private func addPhase() {
        let name = newPhaseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let phase = TodoTask(
            workspaceID: project.workspaceID,
            title: name,
            kind: .phase,
            sortOrder: (project.phaseTasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: project.createdByID
        )
        modelContext.insert(phase)
        phase.project = project
        project.updatedAt = .now
        newPhaseName = ""
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        ProjectDetailView(project: preview.project)
    }
    .modelContainer(preview.container)
}
