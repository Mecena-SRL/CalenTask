import SwiftUI
import SwiftData

/// Triage uno-alla-volta dell'Inbox (S4/D61, ridisegnato v8): una carta al
/// centro — provenienza in chiaro, mazzo che sfuma dietro, barra di
/// avanzamento — e quattro decisioni in un footer coerente: Oggi, Pianifica,
/// Progetto o Elimina. Ogni decisione fa avanzare; lo skip rimanda a dopo.
struct TriageFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: TodoTask.inboxPredicate, sort: \TodoTask.createdAt)
    private var inbox: [TodoTask]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil })
    private var people: [UserProfile]

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    // A5 (audit account) — Smista pescava da TUTTA l'Inbox indipendentemente
    // dallo spazio attivo, disallineato da Calendario/Dashboard/Inbox stessa.
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    private var scopedInbox: [TodoTask] {
        WorkspaceScope.filter(inbox, raw: scopeRaw, id: \.workspaceID)
    }

    /// Rimandate a dopo (questa sessione) e già decise (Oggi/Pianifica non
    /// tolgono il task dall'Inbox, quindi serve ricordarle per avanzare).
    @State private var skippedIDs: Set<UUID> = []
    @State private var handledIDs: Set<UUID> = []
    @State private var sessionTotal = 0
    @State private var planDate: Date?
    @State private var showsPlanPicker = false

    private var queue: [TodoTask] {
        scopedInbox.filter { !skippedIDs.contains($0.id) && !handledIDs.contains($0.id) }
    }

    private var current: TodoTask? { queue.first }
    private var remaining: Int { queue.count }
    private var progress: Double {
        guard sessionTotal > 0 else { return 0 }
        return Double(min(handledIDs.count, sessionTotal)) / Double(sessionTotal)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let task = current {
                    triageContent(task)
                } else {
                    DSEmptyState(
                        icon: handledIDs.isEmpty && skippedIDs.isEmpty ? "tray" : "checkmark.seal",
                        title: skippedIDs.isEmpty ? "Inbox a zero" : "Quasi fatto",
                        subtitle: completionSubtitle
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Smista")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .onAppear { if sessionTotal == 0 { sessionTotal = scopedInbox.count } }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private var completionSubtitle: String {
        if skippedIDs.isEmpty {
            return "Tutto smistato. Bella sensazione, vero?"
        }
        let n = skippedIDs.count
        return "Smistate tutte le altre, \(n) \(n == 1 ? "rimandata" : "rimandate") a dopo."
    }

    // MARK: Contenuto

    private func triageContent(_ task: TodoTask) -> some View {
        VStack(spacing: DS.l) {
            progressHeader

            Spacer(minLength: DS.m)

            card(task)
                .padding(.horizontal, DS.xs)

            if showsPlanPicker {
                DateChipPicker(label: "Pianifica per", date: Binding(
                    get: { planDate },
                    set: { newValue in
                        planDate = newValue
                        if let newValue { plan(task, for: newValue) }
                    }
                ))
                .padding(DS.m)
                .dsSurface(.card)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: DS.m)

            actionBar(task)
        }
        .padding(DS.l)
        .animation(.dsSoft, value: task.id)
        .animation(.dsQuick, value: showsPlanPicker)
    }

    private var progressHeader: some View {
        VStack(spacing: DS.s) {
            HStack {
                Text(remaining == 1 ? "Ultima da smistare" : "\(remaining) da smistare")
                    .font(.dsMeta.weight(.semibold))
                    .contentTransition(.numericText())
                Spacer()
                if let task = current {
                    Button {
                        withAnimation(.dsSoft) {
                            skippedIDs.insert(task.id)
                            resetDraft()
                        }
                    } label: {
                        Label("Salta", systemImage: "arrow.uturn.forward")
                            .font(.dsCaption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            ProgressView(value: progress)
                .tint(AppSection.inbox.tint)
        }
    }

    /// La carta: provenienza in testa, titolo grande, note, metadati — con un
    /// mazzo che sfuma dietro quando ci sono altre carte in coda.
    private func card(_ task: TodoTask) -> some View {
        VStack(alignment: .leading, spacing: DS.m) {
            ProvenanceLabel(provenance: provenance(for: task))

            HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                Image(systemName: task.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.dsMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }

            metadataRow(task)
        }
        .padding(DS.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(.panel)
        .background(deck)
        .id(task.id)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    /// Il mazzo dietro la carta: una o due sagome che sbucano in basso.
    @ViewBuilder
    private var deck: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
        ZStack {
            if remaining > 2 {
                shape.fill(DSColor.surfaceSecondary)
                    .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
                    .padding(.horizontal, DS.l)
                    .offset(y: 18)
                    .opacity(0.5)
            }
            if remaining > 1 {
                shape.fill(DSColor.surfaceSecondary)
                    .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
                    .padding(.horizontal, DS.s)
                    .offset(y: 9)
                    .opacity(0.8)
            }
        }
    }

    private func metadataRow(_ task: TodoTask) -> some View {
        HStack(spacing: DS.s) {
            ForEach(task.orderedTags.prefix(3), id: \.id) { tag in
                TagChip(tag: tag)
            }
            if let dueAt = task.dueAt {
                Label(dueAt.dsRelativeLabel, systemImage: "flag")
                    .font(.dsCaption)
                    .foregroundStyle(task.isOverdue ? DSColor.overdue : .secondary)
            }
            Spacer(minLength: 0)
            Text("Catturata \(task.createdAt.formatted(.relative(presentation: .named)))")
                .font(.dsCaption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Azioni

    private func actionBar(_ task: TodoTask) -> some View {
        HStack(spacing: DS.s) {
            triageAction("Oggi", icon: "sun.max.fill", tint: Color(hex: "#FFB224")) {
                plan(task, for: .now.startOfDay)
            }
            triageAction("Pianifica", icon: "calendar", tint: .teal) {
                withAnimation(.dsQuick) { showsPlanPicker.toggle() }
            }
            Menu {
                if projects.isEmpty {
                    Text("Nessun progetto")
                } else {
                    ForEach(projects, id: \.id) { project in
                        Button(project.name) { assign(task, to: project) }
                    }
                }
            } label: {
                triageLabel("Progetto", icon: "folder.fill", tint: Color(hex: "#6E56CF"))
            } primaryAction: {
                if projects.count == 1, let first = projects.first {
                    assign(task, to: first)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            triageAction("Elimina", icon: "trash", tint: DSColor.overdue) {
                withAnimation(.dsSoft) {
                    task.softDeleteSubtree()
                    handledIDs.insert(task.id)
                    resetDraft()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.s)
    }

    private func triageAction(
        _ label: String, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            triageLabel(label, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func triageLabel(_ label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: DS.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            Text(label)
                .font(.dsCaption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: Logica

    private func provenance(for task: TodoTask) -> TaskProvenance {
        let meID = UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        let peopleMap = Dictionary(people.map { ($0.id, $0.name) },
                                   uniquingKeysWith: { first, _ in first })
        let workspaceMap = Dictionary(workspaces.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        return task.provenance(meID: meID, people: peopleMap, workspaces: workspaceMap)
    }

    private func plan(_ task: TodoTask, for date: Date) {
        withAnimation(.dsSoft) {
            task.dueAt = date
            task.touch()
            handledIDs.insert(task.id)
            resetDraft()
        }
    }

    private func assign(_ task: TodoTask, to project: Project) {
        withAnimation(.dsSoft) {
            task.project = project
            task.workspaceID = project.workspaceID
            task.touch()
            handledIDs.insert(task.id)
            resetDraft()
        }
    }

    private func resetDraft() {
        planDate = nil
        showsPlanPicker = false
    }
}

#Preview {
    TriageFlowView()
        .modelContainer(PreviewSampleData.make().container)
}
