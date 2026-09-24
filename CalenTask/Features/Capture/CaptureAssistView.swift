import SwiftUI
import SwiftData

/// L'assistente live del quick add (S4/D60): anteprima a chip ANNULLABILI
/// di ciò che il parser ha capito (data, priorità, progetto) + autocomplete
/// di #etichette e /progetti mentre digiti. Riusato da cattura rapida e Rapida.
struct CaptureAssistView: View {
    @Binding var text: String
    @Binding var selectedProject: Project?
    @Binding var suppressDate: Bool
    @Binding var suppressPriority: Bool

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    private var parsed: CaptureParser.Result { CaptureParser.parse(text) }

    private var dateMatch: NaturalDateParser.Match? {
        NaturalDateParser.parse(parsed.title)
    }

    private var resolvedProject: Project? {
        if let selectedProject { return selectedProject }
        guard let query = parsed.projectQuery, !query.isEmpty else { return nil }
        return allProjects.first {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var token: (prefix: Character, query: String)? {
        CaptureParser.activeToken(in: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            if let token {
                autocompleteRow(token)
            }
            chipRow
        }
        .animation(.dsQuick, value: text)
    }

    // MARK: Autocomplete (#etichette, /progetti)

    @ViewBuilder
    private func autocompleteRow(_ token: (prefix: Character, query: String)) -> some View {
        let suggestions: [(id: UUID, name: String, color: Color)] = token.prefix == "#"
            ? allTags
                .filter { token.query.isEmpty || $0.name.localizedCaseInsensitiveContains(token.query) }
                .prefix(5)
                .map { ($0.id, $0.name, Color(hex: $0.colorHex)) }
            : allProjects
                .filter { token.query.isEmpty || $0.name.localizedCaseInsensitiveContains(token.query) }
                .prefix(5)
                .map { ($0.id, $0.name, Color(hex: $0.colorHex)) }

        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.s) {
                    ForEach(suggestions, id: \.id) { suggestion in
                        Button {
                            complete(suggestion.name, token: token)
                        } label: {
                            HStack(spacing: DS.xs) {
                                Circle().fill(suggestion.color)
                                    .frame(width: 7, height: 7)
                                Text(token.prefix == "#" ? "#\(suggestion.name)" : suggestion.name)
                                    .font(.dsCaption.weight(.medium))
                            }
                            .padding(.horizontal, DS.s)
                            .padding(.vertical, 3)
                            .background(suggestion.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(suggestion.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func complete(_ name: String, token: (prefix: Character, query: String)) {
        withAnimation(.dsQuick) {
            if token.prefix == "#" {
                text = CaptureParser.completing(text, token: token, with: name)
            } else {
                selectedProject = allProjects.first { $0.name == name }
                text = CaptureParser.removingActiveToken(text)
            }
        }
    }

    // MARK: Chip d'anteprima annullabili

    @ViewBuilder
    private var chipRow: some View {
        let hasChips = (dateMatch != nil && !suppressDate)
            || (parsed.priority != nil && !suppressPriority)
            || resolvedProject != nil
        if hasChips {
            HStack(spacing: DS.s) {
                if let match = dateMatch, !suppressDate {
                    previewChip(
                        icon: "calendar",
                        label: match.hasTime
                            ? match.date.formatted(.dateTime.day().month().hour().minute())
                            : match.date.dsRelativeLabel,
                        tint: .teal
                    ) { suppressDate = true }
                }
                if let priority = parsed.priority, !suppressPriority {
                    previewChip(
                        icon: "exclamationmark.circle",
                        label: priority.label,
                        tint: DSColor.priority(priority)
                    ) { suppressPriority = true }
                }
                if let project = resolvedProject {
                    previewChip(
                        icon: "folder",
                        label: project.name,
                        tint: Color(hex: project.colorHex)
                    ) {
                        selectedProject = nil
                        if let query = parsed.projectQuery {
                            text = text.replacingOccurrences(of: "/\(query)", with: "")
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func previewChip(
        icon: String, label: String, tint: Color, onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.dsCaption.weight(.medium))
            Button {
                withAnimation(.dsQuick) { onRemove() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rimuovi \(label)")
        }
        .padding(.horizontal, DS.s)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Applica il risultato del quick add a una task appena creata.
/// UN punto solo per la logica di salvataggio (cattura, Rapida, menu bar).
@MainActor
enum CaptureApplier {
    static func apply(
        text: String,
        to task: TodoTask,
        selectedProject: Project?,
        suppressDate: Bool,
        suppressPriority: Bool,
        in context: ModelContext
    ) {
        let parsed = CaptureParser.parse(text)
        task.title = parsed.title.isEmpty ? text : parsed.title
        if let priority = parsed.priority, !suppressPriority {
            task.priority = priority
        }
        if let project = selectedProject ?? resolvedProject(parsed, in: context, workspaceID: task.workspaceID) {
            task.project = project
            task.workspaceID = project.workspaceID
        }
        if !suppressDate {
            _ = NaturalDateParser.apply(to: task, from: task.title)
        }
        TagService.syncTags(for: task, in: context)
    }

    private static func resolvedProject(
        _ parsed: CaptureParser.Result, in context: ModelContext, workspaceID: UUID
    ) -> Project? {
        guard let query = parsed.projectQuery, !query.isEmpty else { return nil }
        let projects = (try? context.fetch(FetchDescriptor<Project>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        return projects.first { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

#Preview {
    struct Demo: View {
        @State private var text = "montaggio domani alle 15 !alta #set"
        @State private var project: Project?
        @State private var noDate = false
        @State private var noPriority = false
        var body: some View {
            VStack(alignment: .leading) {
                TextField("Test", text: $text)
                CaptureAssistView(
                    text: $text, selectedProject: $project,
                    suppressDate: $noDate, suppressPriority: $noPriority
                )
            }
            .padding()
        }
    }
    return Demo()
        .modelContainer(PreviewSampleData.make().container)
}
