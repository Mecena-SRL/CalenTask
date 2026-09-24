import SwiftUI
import SwiftData

/// "Sfoglia" (D70) — la radice di catalogo su iPhone (pattern File/Things):
/// progetti, liste smart, persone, strumenti. Dà al telefono ciò che prima
/// viveva solo nella sidebar del Mac.
struct BrowseView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }
    @Binding var path: [AppDestination]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    @Query(filter: TodoTask.openPredicate)
    private var allOpenTasks: [TodoTask]

    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil && $0.projectID == nil },
           sort: \SavedView.createdAt)
    private var allSavedViews: [SavedView]

    // F3 — etichette navigabili anche da Sfoglia.
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    @State private var showsNewProject = false
    @State private var isCreatingSmartList = false
    @State private var showsTags = false

    private var projects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    private var favoriteProjects: [Project] {
        projects.filter(\.isFavorite)
    }

    private var otherProjects: [Project] {
        projects.filter { !$0.isFavorite }
    }

    private var smartLists: [SavedView] {
        WorkspaceScope.filter(allSavedViews, raw: scopeRaw, id: \.workspaceID)
    }

    private var tags: [Tag] {
        WorkspaceScope.filter(allTags, raw: scopeRaw, id: \.workspaceID)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if configuration.isEnabled(.activities) {
                    Section("Attività") {
                        NavigationLink(value: AppDestination.section(.quick)) {
                            Label("Rapida", systemImage: "bolt")
                        }
                    }
                }
                if configuration.isEnabled(.projects) { projectsSection }
                if configuration.isEnabled(.smartLists) { listsSection }
                if configuration.isEnabled(.tags) { tagsSection }
                if configuration.isEnabled(.people) { peopleSection }
                toolsSection
            }
            .navigationTitle("Sfoglia")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    WorkspaceScopePicker()
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .project(let id):
                    ProjectDestinationView(projectID: id)
                case .smartList(let id):
                    SmartListDestinationView(listID: id)
                case .tag(let id):
                    TagDestinationView(tagID: id)
                case .section(let section):
                    if section == .people {
                        PeopleView()
                    } else if section == .quick {
                        QuickModeView()
                    }
                }
            }
            .sheet(isPresented: $showsNewProject) { NewProjectSheet() }
            .sheet(isPresented: $isCreatingSmartList) { SmartListEditorView() }
            .sheet(isPresented: $showsTags) { TagManagerView() }
        }
    }

    // MARK: Progetti

    @ViewBuilder
    private var projectsSection: some View {
        // D75 — i preferiti sempre sott'occhio, sopra il resto.
        if !favoriteProjects.isEmpty {
            Section("Preferiti") {
                ForEach(favoriteProjects, id: \.id) { project in
                    browseProjectLink(project)
                }
            }
        }
        Section("Progetti") {
            ForEach(otherProjects, id: \.id) { project in
                browseProjectLink(project)
            }
            Button {
                showsNewProject = true
            } label: {
                Label {
                    Text("Nuovo progetto…")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func browseProjectLink(_ project: Project) -> some View {
        NavigationLink(value: AppDestination.project(project.id)) {
            projectRow(project)
        }
        .contextMenu {
            ProjectMenuContent(project: project) { viewType in
                UserDefaults.standard.set(viewType.rawValue,
                                          forKey: "lastProjectViewType")
                router.open(projectID: project.id)
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let open = project.tasks.filter { $0.deletedAt == nil && !$0.isDone && !$0.isPhase }.count
        return HStack(spacing: DS.m) {
            Circle()
                .fill(Color(hex: project.colorHex).gradient)
                .frame(width: 12, height: 12)
            Text(project.name)
                .font(.dsMeta.weight(.medium))
                .lineLimit(1)
            // S6/D64 — Smart Status anche qui: la salute a colpo d'occhio.
            let status = project.smartStatus
            if status != .onTrack {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(status.label)
            }
            Spacer()
            if open > 0 {
                Text("\(open)")
                    .font(.dsNumeric)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Liste smart

    @ViewBuilder
    private var listsSection: some View {
        Section("Liste") {
            ForEach(smartLists, id: \.id) { list in
                NavigationLink(value: AppDestination.smartList(list.id)) {
                    smartListRow(list)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(.dsSoft) {
                            list.deletedAt = .now
                            list.updatedAt = .now
                        }
                    } label: {
                        Label("Elimina lista", systemImage: "trash")
                    }
                }
            }
            Button {
                isCreatingSmartList = true
            } label: {
                Label {
                    Text("Nuova lista…")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func smartListRow(_ list: SavedView) -> some View {
        let filters = list.filters
        let count = allOpenTasks
            .filter { $0.workspaceID == list.workspaceID && filters.matches($0) }
            .count
        return Label {
            Text(list.name)
                .font(.dsMeta.weight(.medium))
        } icon: {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.accentColor)
        }
        .badge(count)
    }

    // MARK: Etichette (F3)

    @ViewBuilder
    private var tagsSection: some View {
        if !tags.isEmpty {
            Section("Etichette") {
                ForEach(tags, id: \.id) { tag in
                    NavigationLink(value: AppDestination.tag(tag.id)) {
                        tagRow(tag)
                    }
                }
            }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let count = tag.tasks.filter { $0.deletedAt == nil && !$0.isDone }.count
        return Label {
            Text(tag.name)
                .font(.dsMeta.weight(.medium))
                .lineLimit(1)
        } icon: {
            Image(systemName: "number")
                .foregroundStyle(Color(hex: tag.colorHex))
        }
        .badge(count)
    }

    // MARK: Persone e strumenti

    private var peopleSection: some View {
        Section {
            NavigationLink(value: AppDestination.section(.people)) {
                Label {
                    Text(AppSection.people.label)
                        .font(.dsMeta.weight(.medium))
                } icon: {
                    Image(systemName: AppSection.people.filledSystemImage)
                        .foregroundStyle(AppSection.people.tint)
                }
            }
        }
    }

    private var toolsSection: some View {
        Section {
            if configuration.isEnabled(.tags) {
            Button {
                showsTags = true
            } label: {
                Label {
                    Text("Etichette")
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "number")
                        .foregroundStyle(.indigo)
                }
            }
            }
            Button {
                router.isSettingsOpen = true
            } label: {
                Label {
                    Text("Impostazioni")
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
    }
}

#Preview {
    BrowseView(path: .constant([]))
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
