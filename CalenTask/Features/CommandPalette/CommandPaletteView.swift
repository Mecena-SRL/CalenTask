import SwiftUI
import SwiftData

/// ⌘K (S6/D65): un campo, tutta l'app — sezioni, progetti, liste smart,
/// attività e azioni. Scrivi, Invio, sei già là.
struct CommandPaletteView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    private var configuration: AppConfiguration { .decode(configurationRaw) }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil && $0.projectID == nil },
           sort: \SavedView.createdAt)
    private var smartLists: [SavedView]

    @Query(filter: TodoTask.openPredicate)
    private var openTasks: [TodoTask]

    @State private var query = ""
    @FocusState private var isFocused: Bool

    private struct Command: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let systemImage: String
        let tint: Color
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.m) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Cerca o esegui… (progetti, attività, azioni)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.dsRowTitle)
                    .focused($isFocused)
                    .onSubmit { commands.first?.run() }
            }
            .padding(DS.l)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(commands) { command in
                        Button(action: command.run) {
                            HStack(spacing: DS.m) {
                                Image(systemName: command.systemImage)
                                    .foregroundStyle(command.tint)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(command.title)
                                        .font(.dsMeta.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let subtitle = command.subtitle {
                                        Text(subtitle)
                                            .font(.dsCaption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.l)
                            .padding(.vertical, DS.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .dsHoverHighlight(cornerRadius: 0)
                    }
                    if commands.isEmpty {
                        Text("Nessun risultato per “\(query)”.")
                            .font(.dsMeta)
                            .foregroundStyle(.secondary)
                            .padding(DS.xl)
                    }
                }
                .padding(.vertical, DS.xs)
            }
            .frame(maxHeight: 360)
        }
        .onAppear { isFocused = true }
        #if os(macOS)
        .frame(width: 520)
        #endif
    }

    // MARK: I comandi (filtrati dal testo)

    private var commands: [Command] {
        let all = actionCommands + projectCommands + smartListCommands + taskCommands
        guard !query.isEmpty else { return Array(all.prefix(12)) }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var actionCommands: [Command] {
        var commands = [
            Command(id: "new-task", title: "Nuova attività", subtitle: "Azione",
                    systemImage: "plus.circle.fill", tint: .accentColor) {
                dismiss()
                router.isQuickCaptureOpen = true
            },
            Command(id: "new-request", title: "Nuova richiesta",
                    subtitle: "Azione · richiesta esterna",
                    systemImage: "envelope.arrow.triangle.branch", tint: Color(hex: "#FFB224")) {
                dismiss()
                router.isIntakeOpen = true
            },
        ]
        commands.removeAll { $0.id == "new-request" && !configuration.isEnabled(.externalRequests) }
        commands += configuration.navigationSections.map { section in
            Command(id: "go-\(section.rawValue)", title: "Vai a \(section.label)",
                    subtitle: "Sezione", systemImage: section.filledSystemImage,
                    tint: section.tint) {
                router.go(section)
                dismiss()
            }
        }
        return commands
    }

    private var projectCommands: [Command] {
        guard configuration.isEnabled(.projects) else { return [] }
        return WorkspaceScope.filter(projects, raw: scopeRaw, id: \.workspaceID).map { project in
            Command(id: "project-\(project.id)", title: project.name,
                    subtitle: "Progetto · \(project.smartStatus.label)",
                    systemImage: "folder.fill",
                    tint: Color(hex: project.colorHex)) {
                router.open(projectID: project.id)
                dismiss()
            }
        }
    }

    private var smartListCommands: [Command] {
        guard configuration.isEnabled(.smartLists) else { return [] }
        return WorkspaceScope.filter(smartLists, raw: scopeRaw, id: \.workspaceID).map { list in
            Command(id: "list-\(list.id)", title: list.name, subtitle: "Lista smart",
                    systemImage: "bookmark.fill", tint: .accentColor) {
                router.open(smartListID: list.id)
                dismiss()
            }
        }
    }

    private var taskCommands: [Command] {
        // Le attività entrano solo quando si cerca: il default resta leggero.
        guard query.count >= 2 else { return [] }
        return WorkspaceScope.filter(openTasks, raw: scopeRaw, id: \.workspaceID)
            .filter { $0.title.localizedCaseInsensitiveContains(query) }
            .prefix(8)
            .map { task in
                Command(id: "task-\(task.id)", title: task.title,
                        subtitle: task.project?.name ?? "Inbox",
                        systemImage: task.kind.systemImage, tint: .secondary) {
                    dismiss()
                    router.open(taskID: task.id)
                }
            }
    }
}

#Preview {
    CommandPaletteView()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
